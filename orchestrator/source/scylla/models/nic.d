module scylla.models.nic;
import scylla.core.utils;
import dproto.dproto;

mixin ProtocolBufferFromString!"
	message NetworkInterface {
		string public_ip = 1;
		string private_ip = 2;
		SecurityPolicy secpol = 3;
	}

	enum SecStatus {
		DENY = 0;
		ALLOW = 1;
	}
	message SecurityInPolicy {
		string name = 1;
		string incoming_ip_range = 2;
		string incoming_port_range = 3;
		string outgoing_port_range = 4;
		SecStatus status = 5;
	}

	message SecurityOutPolicy {
		string name = 1;
		string incoming_port_range = 2;
		string outgoing_ip_range = 3;
		string outgoing_port_range = 4;
		SecStatus status = 5;
	}

	message SecurityPolicy {
		repeated SecurityInPolicy ingress = 1;
		repeated SecurityOutPolicy egress = 2;
	}
";

struct IPInfo {
        string macAddress;
        string mainIP;
        string gatewayIP;
};

shared class NICResource : Resource {
	private {
		string _private_ip;
		string _public_ip;
		string _mac;
		string _devName;
		SecurityPolicy _secpol;
		bool _inUse = false;
		bool attached = false;
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
		bool status = false;

		if(attached) {
			status = false;
		}
		return status;
	}

	override bool deploy() {

		import std.format : format;
		import std.random : uniform;

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

	override bool disconnect(ResourceIdentifier id) {
		bool status = false;
		useResource();
		if(canDisconnect(id)) {
		
		}


		releaseResource();
		return status;
	}

	override bool canDisconnect(ResourceIdentifier id) {
		if(_inUse) {
			return false;
		}

		return true;
	}
}
