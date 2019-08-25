module zephyr.models.node_target;
import zephyr.models.base;

struct NodeTarget {
	mixin BaseModel;

	@serializationKeys("ip_address") string ipAddress;
	@serializationKeys("port") ushort port;
	@serializationKeys("hostname") string hostname;
}
