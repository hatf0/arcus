module bap.models.vps;
import firecracker_d.models.client_models;
import std.json;
import asdf;
import std.uuid;

struct VPS {

	enum PlatformTypes {
		firecracker
	};

	enum State {
		provisioned,
		deployed,
		shutoff,
		running
	};

	@serializationKeys("state") State state;
	@serializationKeys("platform") PlatformTypes platform;
	@serializationKeys("os_template") string osTemplate;
	@serializationKeys("hostname") string name;
	@serializationKeys("uuid") string uuid;
	@serializationKeys("node") string node; //node that the box is located on..
	@serializationKeys("public_ip") string ip_address;
	@serializationKeys("owner") string owner; //username 

	@serializationKeys("boot_source") BootSource boot;
	@serializationKeys("drives") Drive[] drives;
	@serializationKeys("machine_config") MachineConfiguration config;
	@serializationKeys("network_interfaces") NetworkInterface[] nics;
	@serializationKeys("drive_sizes") ulong[string] driveSizes;

	string stringify() {
		return this.serializeToJson();
	}

};
