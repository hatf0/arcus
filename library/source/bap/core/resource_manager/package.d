module bap.core.resource_manager;
import std.string;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.datetime;
import bap.core.resource_manager.filesystem;
public import std.variant : Variant;
public import core.sync.mutex;
public import bap.core.resource_manager.proto;
public import bap.core.resource_manager.filesystem;

static __gshared ResourceManager g_ResourceManager;
static __gshared string regionID = "example";
static int activeMutexes = 0;

//TODO: replace with Mutex with ReadWriteMutex?

// Here be dragons..

// dfmt off
mixin template ResourceInjector(string resourceName, string path = "scylla.core") {
	import std.string;
	/* 
	   This dirty little hack allows us to inject resources right at the startup,
	   so we can pre-define some resources that MUST exist at the start. This runs
	   before any code is allowed to interact with/instantiate objects
	*/

	mixin("
		import " ~ path ~ "." ~ resourceName.toLower() ~ "; 
		bool instantiated" ~ resourceName ~ " = 
			() {g_" ~ resourceName ~ "Singleton = new shared(" ~ resourceName ~ "Singleton); 
			    g_ResourceManager.registerClass(\"" ~ resourceName ~ "\", cast(Resource delegate(string))&g_" ~ resourceName ~ "Singleton.instantiate); 
			    return true;
			   }();
	");

}

mixin template MultiInstanceSingleton(string resourceName) {
	mixin("
		final shared class " ~ resourceName ~ "Singleton : ResourceSingleton {
			
			override Resource instantiate(string data) {
				shared(" ~ resourceName ~ ") res = new shared(" ~ resourceName ~")(data);
				return cast(Resource)res;
			}

			this() {
				mtx = new shared(Mutex)();
			}
		}
		static shared(" ~ resourceName ~ "Singleton) g_" ~ resourceName ~ "Singleton;
	");
}

mixin template OneInstanceSingleton(string resourceName) {

	mixin("
		final shared class " ~ resourceName ~ "Singleton : ResourceSingleton {
			private { 
				bool created = false;
			}

			override Resource instantiate(string data) {
				if(created) {
					return null;
				}

				shared(" ~ resourceName ~ ") res = new shared(" ~ resourceName ~ ")(data);
				created = true;
				return cast(Resource)res;
			}

			this() {
				mtx = new shared(Mutex)();
			}
		}

		static shared(" ~ resourceName ~ "Singleton) g_" ~ resourceName ~ "Singleton;"
	);
}

// dfmt on

static __gshared string filePath;
static __gshared string backupPath;
static __gshared string storagePath;

import std.algorithm.searching : canFind;

import std.stdio : writefln;

/*
   This simple FUSE driver ensures that any config files accessed
   are writable, as specified in your file_entry[] array, which was
   passed to the constructor. It is optional to use this class,
   as some resources MAY not need it.
*/

/* 
NOTE: This class is ONLY intended for sub-MB files.
If your metadata is getting to anything ABOVE 10Mb, THIS WILL BECOME A MAJOR ISSUE!
*/

shared class Resource {
	protected {
		bool deployed = false;
		Mutex mtx;
		ResourceIdentifier self;

		DateTime creation_date;
		string[] connections;
	}

	/* 
	   Persistent storage for variables
	   Persists even across restarts of the program
	   Store nothing sensitive in this
	 */
	ResourceStorage storage;

	file_entry[] getFiles() {
		return null;
	}

	abstract string getClass();
	abstract string getStatus();
	abstract bool exportable();

	@property Variant opDispatch(string target)() const {

		Variant ret = 0;

		if (storage != null) {
			string var = target;
			foreach (file; getFiles()) {
				if (file.name == var) {
					Variant storedFile = storage[var];
					return storedFile;
				}
			}
		} else {
			assert(0, "opDispatch called on an object with no storage..");
		}

		return ret;
	}

	ubyte[] exportResource() {
		// The MinimalResource struct
		// ensures that we can keep data
		// even after we have restarted the
		// application. It saves only the 
		// bare minimum, which includes
		// filesystem contents, connections,
		// it's class, it's creation time
		// and nothing else. 
		// It is assumed that the programmer
		// will use the ResourceStorage
		// to store configurations and have
		// it persistent.
		if (!exportable) {
			return null;
		}
		MinimalResource res = MinimalResource();
		DateTime _creation = creation_date;
		res.creation_time = _creation.toISOExtString();
		res.id = self;
		res.deployed = deployed;
		res.connections = g_ResourceManager.getConnections(self);
		if (storage !is null) {
			ResourceStorage _storage = cast(ResourceStorage) storage;
			res.resources = _storage.exportAll();
		}

		res.resourceClass = getClass();

		return res.serialize();
	}

	bool destroy() {
		import std.process, std.file;

		import std.stdio : writefln;

		if (storage is null) {
			return true;
		}

		string path = filePath ~ "/" ~ self.uuid;

		debug writefln("path: %s", path);

		import core.thread, core.time;

		auto umount_tid = spawnProcess(["/usr/bin/umount", "-lf", path]);
		auto umount = tryWait(umount_tid);

		debug writefln("code: %d", umount.status);
		if (umount.status != 0) {
			string[] mounts = readText("/proc/mounts").split('\n');
			bool found = false;
			foreach (mount; mounts) {
				import std.algorithm.searching;

				if (mount.canFind(path)) {
					found = true;
				}
			}

			assert(!found, "failed to unmount a path which is mounted");
		}
		debug writefln("unmounted %s successfully", path);

		debug writefln("trying to remove %s", path);

		/*
		   THIS WILL PROBABLY HANG IF ANYTHING IS IN USE
		   BUT SADLY I CAN'T ADD THREAD.SLEEP BECAUSE NANOSLEEP
		   FUCKS UP CONTROL FLOW SOMEHOW??
		*/

		/* 
		   WTF?
		*/

		while (exists(path) && isDir(path)) {
			try {
				rmdir(path);
			} catch (Exception e) {
			}
		}

		return true;
	}

	bool deploy() {
		/* DANGEROUS */
		if (deployed) {
			return false;
		}

		ResourceStorage st = cast(ResourceStorage) storage;
		if (!(st is null)) {
			ResourceIdentifier id = cast(ResourceIdentifier) self;

			g_ResourceManager.requestMount(st, self);
			deployed = true;
		}
		return true;
	}

	abstract bool connect(ResourceIdentifier id) {
		if (id.zone.zoneId != regionID) {
			return false;
		}
		connections ~= id.uuid;
		return true;
	}

	abstract bool disconnect(ResourceIdentifier id) {
		if (connections.canFind(id.uuid)) {
			connections.remove!(a => a == id.uuid)();
			return true;
		}
		return false;
	}

	abstract bool canDisconnect(ResourceIdentifier id);

	void useResource() shared @safe nothrow @nogc {
		import core.thread;
		import std.datetime;

		while (mtx.tryLock_nothrow() == false) {
			() @trusted { Thread.sleep(1.msecs); }();
		}

		activeMutexes++;

	}

	void releaseResource() shared @safe nothrow @nogc {
		assert(activeMutexes != 0, "releaseResource called when there are no active mutexes!");

		activeMutexes--;
		mtx.unlock_nothrow();
	}
}

/*
   Use the ResourceSingleton base as your main
   constructor for any resource.

   Obtaining the mutex is unnecessary- as this is only
   likely to be accessed by the ResourceManager thread.
*/

shared class ResourceSingleton {
	Mutex mtx;
	abstract Resource instantiate(string data);
	void useResource() shared @safe nothrow @nogc {
		mtx.lock_nothrow();
	}

	void releaseResource() shared @safe nothrow @nogc {
		mtx.unlock_nothrow();
	}

}

shared class OneConnectionResource : Resource { //for example, network interfaces
	bool attached = false;
	ResourceIdentifier owner;
}

/*
   This ResourceManager handles multi-threaded sharing of resources,
   as well as dynamic instantiation at runtime. Classes are imported with the ResourceInjector mixin,
   then instantiated with it's constructor from the singleton instance
   at runtime. This helps make the code more generic, as I don't
   have to write several files dedicated towards specific modules,
   and I can just inject them at runtime.

NOTE: All resources require a singleton which creates a shared
instance of the resource! This is a requirement of the dynamic
instantiation system!
*/
import dfuse.fuse;

class ResourceManager {
	private {
		Fuse[] resourceFS;
		shared(Resource)[string] _resources;
		ResourceIdentifier[][string] _connections;

		Resource delegate(string)[string] _instanceTable;
		string askForUUID() {
			import std.uuid;

			while (true) {
				auto uuid = randomUUID();
				if (!(uuid.toString() in _resources)) {
					return uuid.toString();
				}
			}
		}
	}

	string[] getAllResourceClasses() {
		return _instanceTable.keys.dup;
	}

	string[] getAllResources() {
		return _resources.keys.dup;
	}

	bool isValidClass(string className) {
		if (className in _instanceTable) {
			return true;
		}
		return false;
	}

	void registerClass(string _className, Resource delegate(string) dlg) {
		assert(!(_className in _instanceTable), "Cannot override delegate for class..");

		assert(dlg != null, "dlg was null!");

		_instanceTable[_className] = cast(Resource delegate(string)) dlg;
	}

	ResourceIdentifier instantiateFromBackup(ubyte[] data) {
		MinimalResource res = MinimalResource(data);
		assert(res.resourceClass in _instanceTable, "Non-existant class loaded");

		Resource r = _instanceTable[res.resourceClass](res.id.uuid);
		assert(!(r is null), "Resource was null when attempting to load from a backup.");

		r.creation_date = cast(shared(DateTime)) DateTime.fromISOExtString(res.creation_time);
		_connections[res.id.uuid] = res.connections;

		if (r.storage !is null) {
			ResourceStorage _storage = cast(ResourceStorage) r.storage;
			_storage.importBak(res.resources);
		}

		if (res.deployed) {
			shared(Resource) _s = cast(shared(Resource)) r;
			assert(_s.deploy(), "Deploy failed..");
		}

		_resources[res.id.uuid] = cast(shared(Resource)) r;

		return res.id;
	}

	ResourceIdentifier instantiateResource(string _class) {
		assert(_class in _instanceTable, "Class must exist..");

		string objectUUID = askForUUID();
		Resource r = _instanceTable[_class](objectUUID);

		assert(!(r is null), "Resource was null during instantiation");

		import bap.core.utils;

		r.creation_date = cast(shared(DateTime)) Clock.currTime();

		_resources[objectUUID] = cast(shared Resource) r;

		return id(regionID, objectUUID);
	}

	string resourceStatus(ResourceIdentifier id) {
		if (id.uuid in _resources) {
			shared Resource r = _resources[id.uuid];
			r.useResource();
			string status = r.getStatus().idup;
			r.releaseResource();

			return status;
		} else {
			return "NO_EXIST";
		}
	}

	bool destroyResource(ResourceIdentifier id) {
		if (id.uuid in _resources) {
			if (id.uuid in _connections) {
			}
			shared Resource r = _resources[id.uuid];
			r.useResource();
			bool status = r.destroy();
			r.releaseResource();

			_resources.remove(id.uuid);
			return status;
		}
		return false;
	}

	shared(Resource) getResource(ResourceIdentifier id) {
		if (id.uuid in _resources) {
			return _resources[id.uuid];
		}
		return null;
	}

	bool associateResource(ResourceIdentifier resource, ResourceIdentifier target) {
		if (resource.uuid in _resources) {
			if (target.uuid in _resources) {
				if (resource.uuid in _connections) {
					_connections[resource.uuid] ~= target;
				} else {
					_connections[resource.uuid] = [target];
				}

				if (target.uuid in _connections) {
					_connections[target.uuid] ~= resource;
				} else {
					_connections[target.uuid] = [resource];
				}

				return true;
			}
		}
		return false;
	}

	bool disassociateResource(ResourceIdentifier resource, ResourceIdentifier target) {
		if (resource.uuid in _resources) {
			if (target.uuid in _resources) {
				if (resource.uuid in _connections) {
					if (target.uuid in _connections) {
						if (_connections[resource.uuid].canFind(target)) {
							if (_connections[target.uuid].canFind(resource)) {
								foreach (i, con; _connections[target.uuid]) {
									if (con.uuid == resource.uuid) {
										_connections[target.uuid].remove(i);
									}
								}

								foreach (i, con; _connections[resource.uuid]) {
									if (con.uuid == target.uuid) {
										_connections[resource.uuid].remove(i);
									}
								}
							}
						}

					} else {
						return false;
					}
				} else {
					return false;
				}

			}
		}
		return false;
	}

	void cleanup() {
		import std.stdio;

		debug writefln("called to cleanup!");
		// PROGRAM IS ABOUT TO SHUTDOWN ANYWAYS!
		foreach (d, k; _resources) {
			import std.file : write;

			if (!(k is null)) {
				if (k.exportable()) {
					debug writefln("writing out %s", k.self.uuid);
					write(backupPath ~ "/" ~ k.self.uuid ~ ".bak", k.exportResource());
				}
				debug writefln("destroying resource %s", k.self.uuid);
				assert(k.destroy(), "failed to destroy object");
			}
		}

		writefln("done!");
	}

	bool requestMount(Operations op, ResourceIdentifier id) {
		import std.file;

		string path = filePath ~ "/" ~ id.uuid ~ "/";
		import std.stdio : writefln;

		debug writefln("requested mount to %s", path);
		if (!exists(path)) {
			try {
				mkdir(path);
			} catch (Exception e) {
			}
		}
		import std.parallelism;

		Fuse obj = new Fuse("ResourceStorage", true, true);
		resourceFS ~= obj;
		auto fsRun = task!runMount(obj, op, path);
		fsRun.executeInNewThread();

		return true;
	}

	ResourceIdentifier[] getConnections(ResourceIdentifier id) {
		ResourceIdentifier[] connections;
		if (id.uuid in _connections) {
			ResourceIdentifier[] connMap = _connections[id.uuid];
			foreach (connection; connMap) {
				connections ~= connection;
			}
		}
		return connections;

	}

	this() {
	}

}
