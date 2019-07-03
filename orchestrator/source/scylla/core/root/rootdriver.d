module scylla.core.root.rootdriver;
import std.algorithm.searching;
import core.thread;
import core.time;
import dproto.dproto;
import zmqd;
import scylla.models.rootdriver;
import scylla.core.utils;
import scylla.models.nic;

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
		static void eventHandler() {
			auto broker = Socket(SocketType.pull);
			broker.bind("inproc://rootdriver");
			log(LogLevel.DEBUG, "rootdriver binded");

			bool run = true;
			while(run) {
				auto frame = Frame();
				auto r = broker.tryReceive(frame);
				if(r[1]) {
					RootDriverEvt evt = RootDriverEvt(frame.data);
					

					log(LogLevel.DEBUG, "rootdriver received frame");
				}

				Thread.sleep(1.msecs);
			}
		}

	this() {
		auto thread = new Thread(&eventHandler);
		thread.isDaemon(true);
		thread.start();
	}
}


