module scylla.core.logger.logengine;
import bap.core.resource_manager;
import zmqd;
import std.stdio;
import core.thread, core.time;
import dproto.dproto;

mixin ProtocolBufferFromString!"
	enum LogLevel {
		ERROR = 0;
		WARNING = 1;
		INFO = 2;
		DEBUG = 3;
	}
	message LogEvent {
		required string origin = 1;
		required LogLevel level = 2;
		required string message = 3;
	}
";

shared class LogEngineSingleton : ResourceSingleton {
	private {
		bool created = false;
	}

	override Resource instantiate(string data) {
		assert(!created, "cannot be created more then once.");
		shared(LogEngine) res = new shared(LogEngine)(data);

		created = true;

		return cast(Resource)res;
	}

	this() {
		mtx = new shared(Mutex)();
	}
}

static shared(LogEngineSingleton) g_LogEngineSingleton;


shared class LogEngine : Resource {
	private:
		__gshared bool run = true;
		LogLevel maxLevel = LogLevel.INFO;
		string logFile; 

		void printHelper(LogEvent l) {
			import std.datetime.systime : SysTime, Clock;

			LogLevel level = l.level;
			string origin = l.origin;
			string msg = l.message;

			SysTime currentTime = Clock.currTime();
			string message = "";
			message ~= currentTime.toISOExtString() ~ " [" ~ origin ~ ":"; 
			if((cast(int)level) <= (cast(int)maxLevel)) {
				switch(level) {
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

				if(logFile != "") {
					import std.file : append;
					append(logFile, message);
				}

				switch(level) {
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

			while(run) {
				auto frame = Frame();
				auto r = broker.tryReceive(frame);
				if(r[1]) {
					LogEvent l = LogEvent(frame.data);
					printHelper(l);
				}
				else {
				}
				Thread.sleep(1.msecs);
			}
		}
	public:
		override bool exportable() {
			return false;
		}

		override string getClass() {
			return "LogEngine";
		}

		override string getStatus() {
			return "ACTIVE";
		}

		override bool destroy() {
			writeln("log engine shutting down");
			run = false;
			return true;
		}

		override bool deploy() {
			run = true;
			auto thread = new Thread(cast(void delegate())&workerThread);
			thread.isDaemon(true);
			thread.start();
			return true;
		}

		override bool connect(ResourceIdentifier id) {
			assert(0, "connect called on LogEngine");
		}

		override bool disconnect(ResourceIdentifier id) {
			assert(0, "disconnect called on LogEngine");
		}

		override bool canDisconnect(ResourceIdentifier id) {
			return false;
		}

		this(string file) {
			if(file != "") {
				logFile = file.idup;
			}

			mtx = new shared(Mutex)();

		}
}
