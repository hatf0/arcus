module bap.core.resource_manager;
import std.string;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.datetime;
public import core.sync.mutex;
public import dproto.dproto;

static ResourceManager g_ResourceManager;
static int activeMutexes = 0;


//TODO: replace with Mutex with ReadWriteMutex?

// Here be dragons..
mixin template ResourceInjector(string resourceName) {
	mixin("import " ~ resourceName.toLower() ~ "; bool instantiated" ~ resourceName ~ " = () {g_" ~ resourceName ~ "Singleton = new shared(" ~ resourceName ~ "Singleton); g_ResourceManager.registerClass(\"" ~ resourceName ~ "\", cast(Resource delegate(string))&g_" ~ resourceName ~ "Singleton.instantiate); return true;}();");

}

mixin ProtocolBufferFromString!"
	message ResourceIdentifier {
		ZoneIdentifier zone = 1;
		string uuid = 2;
	}

	message ZoneIdentifier {
		string zoneId = 1;
	}

	message Zone {
		string location = 1;
		string name = 2;
	}
";

shared class Resource {
	Mutex mtx;
	ResourceIdentifier self;
	DateTime creation_date; 

	abstract string getClass();
	abstract string getStatus();
	abstract bool destroy();
	abstract bool deploy();
	abstract bool connect(ResourceIdentifier id);
	abstract bool disconnect(ResourceIdentifier id);
	abstract bool canDisconnect(ResourceIdentifier id);

	void useResource() shared @safe nothrow @nogc 
	{
		import core.thread;
		import std.datetime;
		while(mtx.tryLock_nothrow() == false) {
			() @trusted {Thread.sleep(1.msecs);}();
		}

		activeMutexes++;

	}

	void releaseResource() shared @safe nothrow @nogc
	{
		assert(activeMutexes != 0, "releaseResource called when there are no active mutexes!");

		activeMutexes--;
		mtx.unlock_nothrow();
	}
}

shared class ResourceSingleton {
	Mutex mtx;
	abstract Resource instantiate(string data);
	void useResource() shared @safe nothrow @nogc 
	{
		mtx.lock_nothrow();
	}

	void releaseResource() shared @safe nothrow @nogc
	{
		mtx.unlock_nothrow();
	}

}

shared class OneConnectionResource : Resource { //for example, network interfaces
	bool attached = false;
	ResourceIdentifier owner;
}

class ResourceManager {
	private {
		shared(Resource)[string] _resources;
		ResourceIdentifier[][string] _connections;

		Resource delegate(string)[string] _instanceTable;
		string askForUUID() {
			import std.uuid;
			while(true) {
				auto uuid = randomUUID();
				if(!(uuid.toString() in _resources)) {
					return uuid.toString();
				}
			}
		}	
	}

	void registerClass(string _className, Resource delegate(string) dlg) {
		assert(!(_className in _instanceTable), "Cannot override delegate for class..");

		assert(dlg != null, "dlg was null!");

		_instanceTable[_className] = cast(Resource delegate(string))dlg;
	}

	ResourceIdentifier instantiateResource(string _class) {
		assert(_class in _instanceTable, "Class must exist..");

		string objectUUID = askForUUID();
		Resource r = _instanceTable[_class](objectUUID);

		assert(!(r is null), "Resource was null during instantiation");

		r.creation_date = cast(shared(DateTime))Clock.currTime();

		_resources[objectUUID] = cast(shared Resource)r;
		
		import bap.core.utils;

		return id("example", objectUUID);
	}

	string resourceStatus(ResourceIdentifier id) {
		if(id.uuid in _resources) {
			shared Resource r = _resources[id.uuid];
			r.useResource();
			string status = r.getStatus().idup;
			r.releaseResource();

			return status;
		}
		else {
			return "NO_EXIST";
		}
	}

	bool destroyResource(ResourceIdentifier id) {
		if(id.uuid in _resources) {
			if(id.uuid in _connections) {
				return false;
			}
			shared Resource r = _resources[id.uuid];
			r.useResource();
			bool status = r.destroy();
			r.releaseResource();
			return status;
		}
		return false;
	}

	shared(Resource) getResource(ResourceIdentifier id) {
		if(id.uuid in _resources) {
			return _resources[id.uuid];
		}
		return null;
	}

	bool associateResource(ResourceIdentifier resource, ResourceIdentifier target) {
		if(resource.uuid in _resources) {
			if(target.uuid in _resources) {
				if(resource.uuid in _connections) {
					_connections[resource.uuid] ~= target;
				}
				else {
					_connections[resource.uuid] = [target];
				}

				if(target.uuid in _connections) {
					_connections[target.uuid] ~= resource;
				}
				else {
					_connections[target.uuid] = [resource];
				}

				return true;
			}
		}
		return false;
	}

	bool disassociateResource(ResourceIdentifier resource, ResourceIdentifier target) {
		if(resource.uuid in _resources) {
			if(target.uuid in _resources) {
				if(resource.uuid in _connections) {
					if(target.uuid in _connections) {
						if(_connections[resource.uuid].canFind(target)) {
							if(_connections[target.uuid].canFind(resource)) {
								foreach(i, con; _connections[target.uuid]) {
									if(con.uuid == resource.uuid) {
										_connections[target.uuid].remove(i);
									}
								}

								foreach(i, con; _connections[resource.uuid]) {
									if(con.uuid == target.uuid) {
										_connections[resource.uuid].remove(i);
									}
								}
							}
						}

					}
					else {
						return false;
					}
				}
				else {
					return false;
				}

			}
		}
		return false;
	}

	ResourceIdentifier[] getConnections(ResourceIdentifier id) {
		ResourceIdentifier[] connections;
		if(id.uuid in _connections) {
			ResourceIdentifier[] connMap = _connections[id.uuid];
			foreach(connection; connMap) {
				connections ~= connection;
			}
		}
		return connections;

	}

}
