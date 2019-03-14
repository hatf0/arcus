module zephyr.models.config;
import zephyr.models.base;

struct ZephyrConfig {
    mixin BaseModel;
    @serializationKeys("redis_host") string redisHost;
    @serializationKeys("redis_port") ushort redisPort;
    @serializationKeys("redis_password") string redisPass;
}

