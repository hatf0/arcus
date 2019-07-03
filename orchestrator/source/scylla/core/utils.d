module scylla.core.utils;
import zmqd;
import dproto.dproto;
public import scylla.core.logger.logengine;
public import bap.core.resource_manager;

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
