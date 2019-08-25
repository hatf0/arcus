module bap.core.node;
import bap.models.vps;
import asdf;

struct OnboardData {
	string node_name;
	string communication_key;
	string redis_host;
	ushort redis_port = 6379;
	string redis_password;
};

enum VPSAction {
	remove,
	start,
	reboot,
	stop,
	redeploy,
	statistics,
	auth_key
};

import vibe.web.auth, vibe.web.common;

struct RESTAuth {
	string target_vps;
	string auth_key;
}

interface NodeREST {

	/*
      Onboarding of a node registers it, and gives it all of the necessary information to sync and boot.
  */

	string postOnboard(OnboardData data);

	string postPing();

	@path("vps/new") string postNewVPS(string key, VPS vps);

	@path("vps/:action") string postVPS(string key, string uuid, string _action);

	string getVersion();

};

struct Node {
	@serializationKeys("address") string host;
	@serializationKeys("port") ushort port;
	@serializationKeys("name") string name;
	@serializationKeys("onboarded") bool initialized;
	@serializationKeys("auth_key") string communicationKey;
	@serializationKeys("deployed_vpses") string[] deployedVPS;
	@serializationKeys("statistics") string[string] stats;

	string stringify() {
		return this.serializeToJson();
	}
};
