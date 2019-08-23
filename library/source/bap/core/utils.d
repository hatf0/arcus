module bap.core.utils;
import zmqd;
public import dproto.dproto;
public import bap.core.resource_manager; 

ResourceIdentifier id(string zone, string uuid) {
	ResourceIdentifier i = ResourceIdentifier();
	ZoneIdentifier z = ZoneIdentifier();
	z.zoneId = zone;

	i.zone = z;
	i.uuid = uuid;
	return i;
}

ResourceIdentifier idSelf(string uuid) {
	ResourceIdentifier i = ResourceIdentifier();
	ZoneIdentifier z = ZoneIdentifier();
	z.zoneId = regionID;

	i.zone = z;
	i.uuid = uuid;
	return i;
}

public import bap.core.logger.logengine;
void log(LogLevel l, string msg, string origin = __FILE__) {
	auto requester = Socket(SocketType.push);
	requester.connect("inproc://logger");
	LogEvent _l;
	_l.level = l;
	_l.message = msg.idup;
	_l.origin = origin.idup;
	
	ubyte[] logSerialized = _l.serialize();

	requester.send(logSerialized);
}

void logDebug(string msg, string origin = __FILE__) {
	log(LogLevel.DEBUG, msg, origin);
}

void logInfo(string msg, string origin = __FILE__) {
	log(LogLevel.INFO, msg, origin);
}

void logWarning(string msg, string origin = __FILE__) {
	log(LogLevel.WARNING, msg, origin);
}

void logError(string msg, string origin = __FILE__) {
	log(LogLevel.ERROR, msg, origin);
}
