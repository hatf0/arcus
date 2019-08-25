module valkyrie.models.nic;
import bap.core.utils;
import dproto.dproto;

mixin ProtocolBufferFromString!"
	message NetworkInterface {
		string public_ip = 1;
		string private_ip = 2;
		string dev_name = 3;
		SecurityPolicy secpol = 4;
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

struct IPInfo
{
    string macAddress;
    string mainIP;
    string gatewayIP;
};
