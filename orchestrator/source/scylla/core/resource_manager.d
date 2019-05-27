module scylla.core.resource_manager;
import scylla.zone.zone;
import std.string;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.datetime;
import core.sync.mutex;
import scylla.core.resource;

shared class Resource {
	Mutex mtx;
	bool attached = false;
	string owner_uuid = "NULL";
	string uuid;
	DateTime creation_date; 

	void setOwner(string uuid) {
		useResource();
		//entered a critical section..

		uuid = uuid.idup;
		
		releaseResource();
	}

	abstract string getClass();
	abstract string getStatus();
	abstract bool destroy();
	abstract bool deploy();
	abstract bool connect(ResourceIdentifier id);
	abstract bool disconnect();
	abstract bool canDisconnect();

	void useResource() shared @safe nothrow @nogc 
	{
		mtx.lock_nothrow();
	}

	void releaseResource() shared @safe nothrow @nogc
	{
		mtx.unlock_nothrow();
	}

}

class ResourceManager {
	private {
		shared Resource[string] _resources;
		string[][string] _connections;
		Resource function(string)[string] _instanceTable;
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

	void registerClass(string _className, Resource function(string) dlg) {
		assert(!(_className in _instanceTable), "Cannot override delegate for class..");

		_instanceTable[_className] = dlg;
	}

	bool instantiateResource(string _class) {
		assert(_class in _instanceTable, "Class must exist..");

		string objectUUID = askForUUID();
		Resource r = _instanceTable[_class](objectUUID);
		if(r is null) {
			return false;
		}

		_resources[objectUUID] = cast(shared Resource)r;

		return true;
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
					_connections[resource.uuid] ~= target.uuid;
				}
				else {
					_connections[resource.uuid] = [target.uuid];
				}

				if(target.uuid in _connections) {
					_connections[target.uuid] ~= resource.uuid;
				}
				else {
					_connections[target.uuid] = [resource.uuid];
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
						if(_connections[resource.uuid].canFind(target.uuid)) {
							if(_connections[target.uuid].canFind(resource.uuid)) {
								_connections[target.uuid] = _connections[target.uuid].remove(resource.uuid);
								_connections[resource.uuid] = _connections[resource.uuid].remove(target.uuid);
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
			string[] connMap = _connections[id.uuid];
			foreach(connection; connMap) {
				ZoneIdentifier id2 = new ZoneIdentifier();
				id2.zoneId = id.zone.zoneId;

				ResourceIdentifier rid = new ResourceIdentifier();
				rid.zone = id2;
				rid.uuid = connection;
				connections ~= rid;
			}
		}
		return connections;

	}
	


}

