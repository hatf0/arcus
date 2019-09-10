module scylla.core.server.kintsugi;
import scylla.core.server.server;
import scylla.models.kintsugi;
import bap.models.vps;
import std.file;
import zmqd;
import core.thread, core.time;
import bap.core.utils;
import std.uuid;

alias UUID = NodeId;

// the user should never handle the instance configuration
// it's more of an abstraction away from using the default structs

interface OrchestratorAPI {
@safe:
	@property NodeId[] nodes(); // number of nodes
	@property uint nodeCount();
	@property string node(NodeId index); // retrieve node configuration  
	@property string nodeKey(NodeId index); // get a temporary communication key with node

	@property string launchInstance(NodeId index, ProvisioningInfo info); 
	@property string destroyInstance(NodeId index, UUID instance); 
}

class Kintsugi {
	private {
		Thread workerProc;
	}

	void workerThread() {
		auto worker = Socket(SocketType.rep);
		try {
			worker.bind("tcp://*:5556");
			log(LogLevel.INFO, "vm server worker has binded to port 5556");
		} catch (Exception e) {
			log(LogLevel.ERROR, "vm server was not able to bind..");
		}

		while (true) {
			auto frame = Frame();
			auto r = worker.tryReceive(frame);
			if (r[1]) {
				try { 
					auto act = frame.data.fromProtobuf!KintsugiWorkerAction;
					KintsugiWorkerResponse resp;
					if(act.action == KintsugiWorkerActions.HELLOACTION) {
						resp.responseLevel = Level.INFO;
						resp.msg = productString;
						log(LogLevel.INFO, "received hello message");
					}

					worker.send(resp.toProtobuf.array);
				} catch(Exception e) {
					log(LogLevel.ERROR, "received malformed frame");
				}
			}

			Thread.sleep(dur!"msecs"(1));
		}
	}

	this() {
		log(LogLevel.INFO, "vm proxy server booting");

		workerProc = new Thread(&workerThread);
		workerProc.isDaemon(true);
		workerProc.start();
	}
}
