module bap.core.node;
import bap.models.vps;
import jsonizer;

struct OnboardData {
  string node_name;
  string communication_key;
  string redis_host;
  ushort redis_port = 6379;
  string redis_password;
};
  
interface NodeREST {

  /*
      Onboarding of a node registers it, and gives it all of the necessary information to sync and boot.
  */

  string onboard(OnboardData data);

  string spoolVPS(VPS vps);

  string deleteVPS(string uuid);

  string startVPS(string uuid);

  string rebootVPS(string uuid);
  
  string stopVPS(string uuid);

  string redeployVPS(string uuid);

  string getVPSStats(string uuid);

  string getNodeVersion();
  
};

struct Node {
  mixin JsonizeMe;
  
  @jsonize("address") string host;
  @jsonize("port") ushort port;
  @jsonize("name") string name;
  @jsonize("auth_key") string communicationKey; 
  @jsonize("deployed_vpses") string[] deployedVPS;

	string stringify() {
        import std.json;
        JSONValue j = jsonizer.toJSON(this);
        return j.toString;
	}
};
  
  
