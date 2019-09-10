module bap.core.utils;
import zmqd;
public import bap.core.resource_manager;
public import scylla.internal.zone; 

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
public import bap.internal.logger;

void log(LogLevel l, string msg, string origin = __FILE__) {
	auto ctx = Context();
	auto requester = Socket(ctx, SocketType.req);

	import std.stdio : writeln;
	try { 
		requester.connect("tcp://localhost:6969");
	} catch(ZmqException e) {
		writeln("LOG ERROR: ", e.msg);
	}

	LogEvent _l;
	_l.level = l;
	_l.message = msg.idup;
	_l.origin = origin.idup;

	ubyte[] logSerialized = _l.toProtobuf.array;

	requester.send(logSerialized);

	auto f = Frame();
	requester.receive(f);
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
