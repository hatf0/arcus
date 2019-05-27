module scylla.core.firecracker;
import std.stdio;
import firecracker_d.models.client_models;
import firecracker_d.core.client;
import bap.models.vps;
import std.file;
import std.process;
import core.sys.posix.signal;
import std.concurrency;
import scylla.core.resource_manager;

class FirecrackerResource : Resource {
        private {
            string __socket;
            bool __provisioned = false;
	    bool __deployed = false;;
            string __logPath;
            string __metricsPath;
            FirecrackerAPIClient __client;
            ProcessPipes __vmPipes;
	    bool socketExists() {
		    return exists(__socket);
		}
	    bool isAlive() {
		    if(!socketExists()) {
			return false;
		    }

		    import core.exception;

		    try {
			InstanceInfo.InstanceState state = __client.InstanceInfo.state; 
		    }
		    catch(Exception e){
			return false;
		    }
		    catch(AssertError e) {
			return false;
		    }
		    catch(InvalidMemoryOperationError e)
		    {
			return false;
		    }
		    return true;
	    }
	    bool isRunning() {
		    if(!isAlive()) {
			    return false;
		    }
		    if(__client.InstanceInfo.state == InstanceInfo.InstanceState.Running) {
			    return true;
		    }
		    else {
			    return false;
		    }
	    }
        }

	override string getClass() {
		return "FirecrackerResource";
	}

	override string getStatus() {
		if(isRunning()) {
			return "running";
		}

		if(isAlive()) {
			return "alive";
		}

		if(__provisioned) {
			return "provisioned";
		}

		return "not_provisioned";
	}

	override bool destroy() {
		if(isRunning()) {
			return false;
		}

		return true;
	}

	override bool deploy() {
		return true;
	}

	void eventListener() {
		while(true) {
			receive(
				(Tid sender, InstanceAction act) {
					if(act.action == InstanceAction.Action.START) {

					}
			
				},

				(Tid sender, ProvisioningInfo info) {
				
				}
			);

		}
	}

        this(string id) {
            __id = id.idup;
            writefln("id: %s", __id);
            __socket = "/tmp/fc-" ~ __id ~ "-socket";
            __logPath = "/tmp/fc-" ~ __id ~ "-log";
            __metricsPath = "/tmp/fc-" ~ __id ~ "-metrics";
            std.file.write(__logPath, "");
            std.file.write(__metricsPath, "");

	    auto tid = spawn(&eventListener, id);
	    register(id, tid);

        }

        ~this() {
            kill(__vmPipes.pid.processID, SIGKILL);
        }


}
