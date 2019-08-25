module scylla.models.config.scylla;
import std.stdio;
import std.file;
import asdf;

struct ScyllaConfig {
	@serializationKeys("redis_host") string redisHost;
	@serializationKeys("redis_port") ushort redisPort;
	@serializationKeys("redis_password") string redisPassword;
	@serializationKeys("vps_storage_path") string vpsStoragePath;
	@serializationKeys("vps_image_path") string vpsImagePath;
	@serializationKeys("listen_port") ushort port;
	@serializationKeys("listen_address") string listenAddress;

	string stringify() {
		with (asdf) {
			return this.serializeToJson();
		}
	}

}
