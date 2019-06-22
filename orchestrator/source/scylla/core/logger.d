module scylla.core.logger;
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

class LogEngine {
	private:
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

			while(true) {
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
		this(string file, LogLevel level) {
			if(file != "") {
				logFile = file.idup;
			}

			maxLevel = level;
			auto thread = new Thread(&workerThread);
			thread.isDaemon(true);
			thread.start();

			Thread.sleep(100.msecs);
		}
}
