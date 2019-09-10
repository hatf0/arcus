module bap.core.resource_manager;
import std.string;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.datetime;
import bap.internal.fs.filesystem;
public import std.variant : Variant;
public import core.sync.mutex;
public import bap.core.resource_manager.filesystem;
public import scylla.internal.zone;
public import google.protobuf;
public import std.array : array;
import std.exception : enforce;

static __gshared ResourceManager g_ResourceManager;
static __gshared string regionID = "example";
static int activeMutexes = 0;

//TODO: replace with Mutex with ReadWriteMutex?

// Here be dragons..

struct Exportable {
}

struct Storage {
}

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
			() {
				import " ~ path ~ "." ~ resourceName.toLower ~ "; 
				g_" ~ resourceName ~ "Singleton = new shared(" ~ resourceName ~ "Singleton); 
			    
				g_ResourceManager.registerClass!(" ~ resourceName ~ ")(
						cast(Variant delegate(string))&g_" ~ resourceName ~ "Singleton.instantiate); 
			    	return true;
			}();
	");

}

mixin template MultiInstanceSingleton(string resourceName) {
	mixin("
		final shared class " ~ resourceName ~ "Singleton : ResourceSingleton!(" ~ resourceName ~ ") {
			
			override Object instantiate(string data) {
				" ~ resourceName ~ " res = new " ~ resourceName ~"(data);
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
		final shared class " ~ resourceName ~ "Singleton : ResourceSingleton!(" ~ resourceName ~ ") {
			private { 
				bool created = false;
			}

			override Variant instantiate(string data) {
				Variant v = null;
				if(created) {
					return v;
				}


				Resource!(" ~ resourceName ~ ") _res = new Resource!(" ~ resourceName ~ ")(data);

				v = _res;
				created = true;
				return v;
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

import std.traits;
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

/*
   Ensure that we are the only person on this, then use it
*/

string EnsureNonNull(int length = 50)() {
	import std.conv : to;
	enum EnsureNonNull = "
			import std.stdio : writeln;
			writeln(\"Active mutexes: \", activeMutexes);
			int __waitCount = 0;
			while(activeMutexes != 0) {
				if(__waitCount % 10 == 0) {
					writeln(\"Waiting on mutex release on object\");
				}

				enforce(__waitCount == " ~ to!string(length) ~ ", \"Wait count should never be this high.\");
					
				import core.thread, core.time;
				Thread.sleep(1.seconds);
				__waitCount++;

			}

			assert(!_inside.isEmpty, \"_inside should never be null!\");

			activeMutexes++;
			scope(exit) activeMutexes--;
	";
	return EnsureNonNull;
}

interface GenericResource {
	@property bool exportable();

	static bool hasStorage();

	static string getClass();

	@property string status(string setStatus);
	@property string status();

	@property ResourceIdentifier self();

	@property DateTime creation();
	@property DateTime creation(DateTime date);

	@property ResourceStorage storage();
	@property ResourceStorage storage(ResourceStorage storage);

	ubyte[] exportResource();
	bool destroy();
	bool deploy();
	bool connect(ResourceIdentifier id);
	bool disconnect(ResourceIdentifier id);
	bool canDisconnect(ResourceIdentifier id);
}

// A resource is typically viewed as bei

class Resource(T) : GenericResource {

	Unique!T _inside;
	Mutex mtx;
	ResourceIdentifier _self;

	DateTime creation_date;
	ResourceIdentifier[] connection_table;
	file_entry[] file_table;

	ResourceStorage _storage;
	string _status;
	bool deployed = false;

	file_entry[] getFiles() {
		mixin(EnsureNonNull());

		static if(hasUDA!(T, Storage)) {
			return _inside.files;
		}
		else {
			assert(0);
		}
	}

	@property bool exportable() {
		static if(hasUDA!(T, Exportable)) {
				return true;
		}
		return false;
	}

	static bool export_() {
		static if(hasUDA!(T, Exportable)) {
				return true;
		}
		return false;
	}

	static bool hasStorage() {
		static if(hasUDA!(T, Storage)) {
				return true;
		}
		return false;
	}

	static string getClass() {
		return __traits(identifier, T);
	}

	@property string status(string setStatus) {
		_status = setStatus;
		return _status;
	}

	@property string status() {
		return _status;
	}

	@property ResourceIdentifier self() {
		return _self;
	}

	@property DateTime creation() {
		return creation_date;
	}

	@property DateTime creation(DateTime date) {
		creation_date = date;
		return creation_date;
	}

	@property ResourceStorage storage() {
		assert(hasStorage(), "Called to get Storage on an object which has no storage.");

		return _storage;
	}

	@property ResourceStorage storage(ResourceStorage st) {
		assert(hasStorage(), "Called to set Storage on an object which has no storage.");

		_storage = st;
		return storage;
	}

	/*	@property Variant opDispatch(string target)() const {
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
	*/

	/*
		This borrows the object inside,
		nulls it, and sets a mutex. 
	*/

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
		mixin(EnsureNonNull());
		if (!export_) {
			return null;
		}

		MinimalResource res = MinimalResource();

		DateTime _creation = creation_date;
		res.creationTime = _creation.toISOExtString();
		res.id = self;
		res.deployed = deployed;
		res.connections = connection_table;
		if (hasStorage()) {
			ResourceStorage _storage = cast(ResourceStorage) storage;
			res.resources = _storage.exportAll();
		}

		res.resourceClass = getClass();

		return res.toProtobuf.array;
	}

	bool destroy() {
		mixin(EnsureNonNull());

		_inside.destroy();

		import std.process, std.file;

		import std.stdio : writefln;

		if (!hasStorage()) {
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
		mixin(EnsureNonNull());

		if (deployed) {
			return false;
		}

		_inside.deploy();

		static if(hasStorage()) {
			ResourceStorage st = cast(ResourceStorage) storage;
			if (!(st is null)) {
				ResourceIdentifier id = cast(ResourceIdentifier) self;

				g_ResourceManager.requestMount(st, self);
			}
		}

		deployed = true;
		return true;
	}

	bool connect(ResourceIdentifier id) {
		mixin(EnsureNonNull());

		if (id.zone.zoneId != regionID) {
			return false;
		}
		connection_table ~= id;
		_inside.connect(id);
		return true;
	}

	bool disconnect(ResourceIdentifier id) {
		mixin(EnsureNonNull());

		foreach (i, c; connection_table) {
			if (c.uuid == id.uuid) {
				connection_table.remove(i);
			}
		}

		if (_inside.canDisconnect(id)) {
			_inside.disconnect(id);
			return true;
		}
		return false;
	}

	bool canDisconnect(ResourceIdentifier id) {
		mixin(EnsureNonNull());
		if (!deployed) {
			return false;
		}

		return _inside.canDisconnect(id);
	}

	Unique!(T) useResource() {
		import core.thread;
		import std.datetime;

		while (mtx.tryLock_nothrow() == false) {
			() @trusted { Thread.sleep(1.msecs); }();
		}

		activeMutexes++;

		return _inside.release;
	}

	void releaseResource(ref Unique!(T) res) {
		assert(activeMutexes != 0, "releaseResource called when there are no active mutexes!");

		//consume it rawr
		import std.algorithm.mutation : move;

		_inside = res.release;

		activeMutexes--;
		mtx.unlock_nothrow();
	}

	this(string data) {
		_inside = new T(data);

		assert(!_inside.isEmpty, "_inside is null");

		mtx = new Mutex();
	}

	this(ref T inside) {
		import std.algorithm.mutation : move;

		_inside = inside;

		mtx = new Mutex();
	}
}

/*
   Use the ResourceSingleton base as your main
   constructor for any resource.

   Obtaining the mutex is unnecessary- as this is only
   likely to be accessed by the ResourceManager thread.
*/

shared class ResourceSingleton(T) {
	Mutex mtx;
	abstract Variant instantiate(string data);

	void useResource() shared @safe nothrow @nogc {
		mtx.lock_nothrow();
	}

	void releaseResource() shared @safe nothrow @nogc {
		mtx.unlock_nothrow();
	}

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
import std.typecons;
import std.typetuple;

class ResourceManager {
	private {
		Fuse[] resourceFS;
		Variant[string] _resources;
		ResourceIdentifier[][string] _connections;
		Variant delegate(string)[string] _instanceTable;

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

	void registerClass(_class)(Variant delegate(string) dlg) {
		assert(!(__traits(identifier, _class) in _instanceTable),
				"Cannot override delegate for class..");

		assert(dlg != null, "dlg was null!");

		_instanceTable[__traits(identifier, _class)] = cast(Variant delegate(string)) dlg;
	}

	ResourceIdentifier instantiateFromBackup(ubyte[] data) {
		MinimalResource res = data.fromProtobuf!MinimalResource;
		assert(res.resourceClass in _instanceTable, "Non-existant class loaded");

		auto _r = _instanceTable[res.resourceClass](res.id.uuid);
		auto r = _r.get!(GenericResource);

		assert(!(r is null), "Resource was null when attempting to load from a backup.");

		r.creation = cast(shared(DateTime)) DateTime.fromISOExtString(res.creationTime);
		_connections[res.id.uuid] = res.connections;

		if (r.storage !is null) {
			ResourceStorage _storage = cast(ResourceStorage) r.storage;
			_storage.importBak(res.resources);
		}

		if (res.deployed) {
			assert(r.deploy(), "Deploy failed..");
		}

		_resources[res.id.uuid] = _r;

		return res.id;
	}

	ResourceIdentifier instantiateResource(_class)() {
		assert(__traits(identifier, _class) in _instanceTable, "Class must exist..");

		string className = __traits(identifier, _class);

		string objectUUID = askForUUID();
		auto _r = _instanceTable[className](objectUUID);
		auto _k = _r.get!(GenericResource);

		assert(!(_k is null), "Resource was null during instantiation");

		_k.creation = cast(shared(DateTime)) Clock.currTime();

		import bap.core.utils;

		_resources[objectUUID] = _r;

		debug import std.stdio : writeln;
		debug writeln("Registered object with class: ", className, " UUID: ", objectUUID);

		return id(regionID, objectUUID);
	}

	Resource!T getResource(T)(ResourceIdentifier id) {
		if (id.uuid in _resources) {
			auto o = _resources[id.uuid];
			if (o.peek!(Resource!T)) {
				Resource!T res = o.get!(Resource!T);
				return res;
			}
		}
		assert(0);
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

		import core.memory;

		//GC.disable;

		debug writefln("called to cleanup!");
		foreach (d, _k; _resources) {
			import std.file : write;

			auto k = _k.get!(GenericResource);

			if (k !is null) {
				if (k.exportable()) {
					debug writefln("writing out %s", k.self.uuid);
					write(backupPath ~ "/" ~ k.self.uuid ~ ".bak", k.exportResource());
				}
				debug writefln("destroying resource %s", k.self.uuid);
				assert(k.destroy(), "failed to destroy object");
			}
		}

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

}
