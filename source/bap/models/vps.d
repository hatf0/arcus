module bap.models.vps;
import firecracker_d.models.client_models;
import std.json;
import jsonizer;
import std.uuid;

struct VPS {
  mixin JsonizeMe;

  enum PlatformTypes {
    firecracker
  };

  enum State {
    provisioned,
    deployed,
    shutoff,
    running
  };
    

  @jsonize("state") State state;
  @jsonize("platform") PlatformTypes platform;
  @jsonize("hostname") string name;
  @jsonize("uuid") string uuid;
  @jsonize("node") string node; //node that the box is located on..
  @jsonize("public_ip") string ip_address;

  @jsonize("boot_source") BootSource boot;
  @jsonize("drives") Drive[] drives;
  @jsonize("machine_config") MachineConfiguration config;
  @jsonize("network_interfaces") NetworkInterface[] nics;

  string stringify() {
        JSONValue j = jsonizer.toJSON(this);
        return j.toString;
  }

};






