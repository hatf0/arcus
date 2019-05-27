module scylla.core.resource;
import scylla.zone.zone;
import scylla.core.resource_manager;

/*
shared class NICResource : Resource {
	private {
		string _private_ip;
		string _public_ip;
		string _mac;
		string _devName;
		SecurityPolicy _secpol;
		bool _inUse = false;
	}

	NetworkInterface getRepresentation() {
		useResource();

		NetworkInterface n = new NetworkInterface();
		n.secpol = cast(SecurityPolicy)_secpol;
		n.publicIp = _public_ip;
		n.privateIp = _private_ip;

		releaseResource();
		return n;
	}

	override string getClass() {
		return "NIC";
	}

	override string getStatus() {
		if(_mac == "") {
			return "NO_MAC";
		}

		if(_private_ip == "") {
			return "NO_PRIV_IP";
		}

		if(_public_ip == "") {
			return "NO_PUBLIC_IP";
		}

		if(!attached) {
			return "NOT_ATTACHED";
		}

		return "OK";
	}

	override bool destroy() {
		useResource();

		bool status = false;

		if(canDisconnect()) {
			status = true;
		}
		if(attached) {
			status = false;
		}

		releaseResource();
		return status;
	}

	override bool deploy() {
		useResource();

		import std.format : format;
		import std.random : uniform;
		send(cast(Tid)allocator, thisTid, cast(string)uuid);
		IPInfo info;
		receiveTimeout(dur!"seconds"(5), (IPInfo i) { writeln("received"); info = i; });

		releaseResource();
		return true;
	}

	override bool connect(ResourceIdentifier id) {
		bool status = false;
		useResource();
		if(!attached) {
			status = true;
		}

		releaseResource();
		return status;
	}

	override bool disconnect() {
		bool status = false;
		useResource();
		if(canDisconnect()) {
		
		}


		releaseResource();
		return status;
	}

	override bool canDisconnect() {
		if(_inUse) {
			return false;
		}

		return true;
	}

	Resource constructor(string uuid) {
		auto r = new shared NICResource();
		import core.sync.mutex;
		mtx = new shared Mutex();
		uuid = uuid;

		return cast(Resource)r;
	}

    }

    this() {
        allocator = spawn(&ipAllocator);
    }
*/
