module scylla.core.rootdriver;
import scylla.nic.nic;
import std.algorithm.searching;
import std.concurrency;

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
		void eventHandler() {
			bool run = true;
			while(run) {
				receive((Tid sender, string event, string[string] data) { 
					switch(event) {
						case "nic.allocate":
							string ip = allocateNewIP();
							string mac = allocateNewMAC();
							string iface = allocateNewNIC();
							if(!assignNICProperties(iface, ip, mac)) { 
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
						case "shutdown":
							run = false;
							send(sender, true, "");
							break;
						default:
							send(sender, false, "");
							break;
					}
				}, (Tid sender, string nic, SecurityPolicy secpol) {
					updateNICNetworkRules(nic, secpol);
					send(sender, true, "");
				});
			}
		}

	this() {
		auto tid = spawn(&eventHandler);
		register(tid, "scylla.core.rootdriver");
	}
}


