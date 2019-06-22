module scylla.core.rootdriver;
import std.algorithm.searching;
import std.concurrency;
import dproto.dproto;
import scylla.models.nic;

mixin ProtocolBufferFromString!"
	enum Events {
		ALLOCATE_NIC = 0;
		ALLOCATE_IP = 1;
		ALLOCATE_NIC = 2;
		ADD_NIC_TO_BR = 3;
		UPDATE_NIC_NSG = 4;
		UPDATE_NIC = 5;
	}

	message UpdateNICNSG {
		string iface = 1;
		SecurityPolicy secpol = 2;
	}

	message AllocateMAC {

	}

	message AllocateIP {

	}

	message AllocateNIC {

	}

	message AddNICToBridge {
		string iface = 1;
		string bridge = 2;
	}

	message UpdateNIC {
		string iface = 1;
		string ip = 2;
		string mac = 3;
	}

	message RootDriverEvt {
		Events evt = 1;
		AllocateMAC allocateMAC = 2;
		AllocateIP allocateIP = 3;
		AllocateNIC allocateNIC = 4;
		AddNICToBridge addNICToBridge = 5;
		UpdateNICNSG updateNICNSG = 6;
		UpdateNIC updateNIC = 7;
	}


";

class RootDriver {
	//the only class which should ever have root.
	private:
		string[] allocatedIPRange;
		string[] allocatedMACRange;

		string allocateNewIP() {
			return "";
		}

		string allocateNewMAC() {
			return "";
		}

		string allocateNewNIC() { 
			return "";
		}

		bool assignNICProperties(string nic, string ip, string mac) {
			return false;
		}

		bool assignNICToBridge(string bridge, string nic) {
			return false;
		}

		bool updateNICNetworkRules(string nic, SecurityPolicy secpol) {
			return false;
		}

	public:
		void generalEventHandler(Tid sender, string event, immutable(string)[string] _data) {
			string[string] data = cast(string[string])_data;
			switch(event) {
				case "nic.allocate":
					string ip = this.allocateNewIP();
					string mac = this.allocateNewMAC();
					string iface = this.allocateNewNIC();
					if(!this.assignNICProperties(iface, ip, mac)) { 
						send(sender, false, "assign_fail");
					}
					send(sender, true, iface);
					break;
				case "nic.bridge":
					if(!data.keys.canFind("bridge") || !data.keys.canFind("nic")) {
						send(sender, false, "");
						break;
					}

					string bridge = data["bridge"];
					string nic = data["nic"];
					send(sender, true, "");
					break;
				default:
					send(sender, false, "");
					break;
			}
		}

		void nsgHandler(Tid sender, string nic, SecurityPolicy secpol) {

		}
		static void eventHandler() {
			bool run = true;
			while(run) {
				receive(
					&generalEventHandler, 
					&nsgHandler
				);
			}
		}

	this() {
		auto tid = spawn(&eventHandler);
		register("scylla.core.rootdriver", tid);
	}
}


