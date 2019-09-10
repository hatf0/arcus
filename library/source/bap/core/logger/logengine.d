module bap.core.logger.logengine;
import bap.core.resource_manager;
import zmqd;
import std.stdio;
import core.thread, core.time;
import std.file : append;
import bap.internal.logger : LogLevel, LogEvent;
import bap.core.utils;

mixin OneInstanceSingleton!("LogEngine");

class LogEngine {
private:
	void logInfo(string origin, string msg) {
		LogEvent l;
		l.level = LogLevel.INFO;
		l.origin = origin;
		l.message = msg;
		printHelper(l);
	}

	void logError(string origin, string msg) {
		LogEvent l;
		l.level = LogLevel.ERROR;
		l.origin = origin;
		l.message = msg;
		printHelper(l);
	}

	Thread thread;
	__gshared bool run = true;
	LogLevel maxLevel = LogLevel.INFO;

	void printHelper(LogEvent l) {
		import std.datetime.systime : SysTime, Clock;

		LogLevel level = l.level;
		string origin = l.origin;
		string msg = l.message;

		SysTime currentTime = Clock.currTime();
		string message = "";
		message ~= currentTime.toISOExtString() ~ " [" ~ origin ~ ":";
		if ((cast(int) level) <= (cast(int) maxLevel)) {
			switch (level) {
			case LogLevel.ERROR:
				message ~= "ERROR";
				break;
			case LogLevel.WARNING:
				message ~= "WARNING";
				break;
			case LogLevel.INFO:
				message ~= "INFO";
				break;
			case LogLevel.DEBUG:
				message ~= "DEBUG";
				break;
			default:
				message ~= "UNKNOWN";
				break;
			}

			message ~= "] " ~ msg;

			if (logFile != "") {
				append(logFile, message ~ "\n");
			}

			switch (level) {
			case LogLevel.ERROR:
				message = "\u001b[31;1m" ~ message;
				break;
			case LogLevel.WARNING:
				message = "\u001b[33;1m" ~ message;
				break;
			case LogLevel.INFO:
				message = "\u001b[36;1m" ~ message;
				break;
			case LogLevel.DEBUG:
				message = "\u001b[38;5;245m" ~ message;
				break;
			default:
				break;
			}

			message ~= "\u001b[0m";
			writeln(message);
		}
	}

	void workerThread() {
		auto broker = Socket(SocketType.pull);
		broker.bind("inproc://logger");

		while (run) {
			auto frame = Frame();
			auto r = broker.tryReceive(frame);
			if (r[1]) {
				ubyte[] dat = frame.data;
				LogEvent l = dat.fromProtobuf!LogEvent;
				printHelper(l);
			}

			Thread.sleep(10.msecs);

		}
	}

public:
	string logFile;
	bool destroy() {
		writeln("log engine shutting down");
		run = false;

		Thread.sleep(100.msecs);

		return true;
	}

	bool deploy() {
		run = true;

		LogEvent l;
		l.origin = "startup";
		l.level = LogLevel.INFO;
		l.message = "LogEngine initialized..";
		printHelper(l);

		thread = new Thread(cast(void delegate())&workerThread);
		Thread _thread = cast(Thread) thread;
		_thread.isDaemon(true);
		_thread.start();
		return true;
	}

	bool connect(ResourceIdentifier id) {
		assert(0, "connect called on LogEngine");
	}

	bool disconnect(ResourceIdentifier id) {
		assert(0, "disconnect called on LogEngine");
	}

	bool canDisconnect(ResourceIdentifier id) {
		return false;
	}

	this(string uuid) {
	}
}
