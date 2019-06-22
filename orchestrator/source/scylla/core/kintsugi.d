module scylla.core.kintsugi;
import scylla.core.server;
import scylla.core.firecracker;
import bap.models.vps;
import std.file;
import zmqd;
import core.thread, core.time;
import scylla.core.utils;
import dproto.dproto;

mixin ProtocolBufferFromString!"
	
	message KintsugiWorkerAction {
		enum KintsugiWorkerActions {
			INSTANCEACTION = 0;
			NICACTION = 1;
			DRIVEACTION = 2;
			NODEACTION = 3;
			ZONEACTION = 4;
			CONNECTACTION = 5;
		}

		KintsugiWorkerActions action = 1;
		optional InstanceAction instanceAction = 2;
		optional NICAction nicAction = 3; 
		optional DriveAction driveAction = 4;
		optional ZoneAction zoneAction = 5;

	}

	message ConnectionAction {
		enum ConnectionType {
			CONNECT = 0;
			DISCONNECT = 1;
		}

		ConnectionType connectionType = 1;
		required ResourceIdentifier target = 2;
		required ResourceIdentifier client = 3;
	}


	
	message ZoneAction {
		enum Action {
			ENUMERATERESOURCES = 0;
			ENUMERATEZONES = 1;
		}
		Action act = 1;
		optional ZoneIdentifier zone = 2;
	}
	
	message DriveAction {

	}

	message NICAction {
		enum Action { 
			ASSIGNMAC = 0;
			ASSIGNIP = 1;
			LIST = 2;
		}
		Action act = 1;
		optional ResourceIdentifier id = 2;
		optional ZoneIdentifier zone = 3;
	}


	message ProvisioningInfo {
		string hostname = 1;
		int32 vcpus = 2;
		int64 ram = 3;
		string template = 4;
	}
	
	message InstanceUpdateInfoAction {
		ResourceIdentifier id = 1;
		ProvisioningInfo update = 2;
	}

	message GeneralReply {
		int32 code = 1;
		string info = 2;
	}

	message InstanceAction {
		enum Action {
			START = 0;
			STOP = 1;
			REBOOT = 2;
			REDEPLOY = 3;
			RECOVERY = 4;
			LOG = 5;
			DEPLOY = 6;
			UPDATEINFO = 7;
			UPDATEOS = 8;
			LIST = 9;
		}
		Action act = 1;
		optional ZoneIdentifier zone = 2;
		optional ResourceIdentifier id = 3;
		optional ProvisioningInfo deployInfo = 4; 
		optional InstanceUpdateInfoAction updateInfo = 5; 
	}

";


class Kintsugi {
    private {
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
	    }
    }


    this() 
    {
	    log(LogLevel.INFO, "vm server booting");
    }
}
