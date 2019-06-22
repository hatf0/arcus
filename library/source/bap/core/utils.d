module bap.core.utils;
import bap.core.resource_manager; 

ResourceIdentifier id(string zone, string uuid) {
	ResourceIdentifier i = ResourceIdentifier();
	ZoneIdentifier z = ZoneIdentifier();
	z.zoneId = zone;

	i.zone = z;
	i.uuid = uuid;
	return i;
}
