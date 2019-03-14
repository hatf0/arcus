module scylla.models.config;
import jsonizer;
import std.stdio;
import std.file;

struct ScyllaConfig {
    mixin JsonizeMe;
    @jsonize("onboard") bool onboarded;
    @jsonize("comm_key") string communicationKey;
    @jsonize("node_name") string nodeName;
    @jsonize("redis_host") string redisHost;
    @jsonize("redis_port") ushort redisPort;
    @jsonize("redis_password") string redisPassword;
    @jsonize("vps_storage_path") string vpsStoragePath;
    @jsonize("vps_image_path") string vpsImagePath;
    @jsonize("listen_port") ushort port;
    @jsonize("listen_address") string listenAddress;

    string stringify() {
        import std.json;
        JSONValue j = jsonizer.toJSON(this);
        return j.toString;
    }

}
