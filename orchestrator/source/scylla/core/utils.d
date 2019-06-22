module scylla.core.utils;
import zmqd;
import dproto.dproto;
public import scylla.core.logger;

mixin ProtocolBufferFromString!"
	message ResourceIdentifier {
		ZoneIdentifier zone = 1;
		string uuid = 2;
	}

	message ZoneIdentifier {
		string zoneId = 1;
	}

	message Zone {
		string location = 1;
		string name = 2;
	}
";

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
