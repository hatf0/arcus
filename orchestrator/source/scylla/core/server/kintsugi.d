module scylla.core.server.kintsugi;
import scylla.core.server.server;
import scylla.models.kintsugi;
import bap.models.vps;
import std.file;
import zmqd;
import core.thread, core.time;
import scylla.core.utils;
import dproto.dproto;

class Kintsugi {
    private {
	Thread workerProc;
	string[string] vms;
    }

    void workerThread() {
	    auto worker = Socket(SocketType.pull);
	    try { 
		    worker.bind("tcp://*:5556");
		    log(LogLevel.INFO, "vm server worker has binded to port 5556");
	    } catch(Exception e) {
		    log(LogLevel.ERROR, "vm server was not able to bind..");
	    }

	    while(true) {
		    auto frame = Frame();
		    auto r = worker.tryReceive(frame);
		    if(r[1]) {

		    }

		    Thread.sleep(dur!"msecs"(1));
	    }
    }


    this() 
    {
	    log(LogLevel.INFO, "vm server booting");

	    workerProc = new Thread(&workerThread);
	    workerProc.isDaemon(true);
	    workerProc.start();
    }
}
