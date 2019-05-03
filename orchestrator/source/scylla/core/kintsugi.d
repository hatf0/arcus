module scylla.core.kintsugi;
import std.stdio;
import scylla.core.server;
import scylla.core.firecracker;
import bap.models.vps;
import std.file;
import std.concurrency;
import std.process;
import std.algorithm.searching;
import core.exception;
import std.string;
import scylla.core.resource_manager;
import scylla.zone.zone;
import scylla.nic.nic;

class Kintsugi {
    private {
        import core.sys.posix.unistd;
        FirecrackerVM[string] servers;
        Tid allocator;
        __gshared string[] allocatedIPs;
        __gshared string[] allocatedMACs;

        bool vmExists(string uuid) {
            if(servers.keys.canFind(uuid)) {
                    return true;
            }
            return false;
        }

        bool vmAlive(string uuid) {
            if(vmExists(uuid)) {
                if(servers[uuid].isAlive()) {
                    return true;
                }
            }
            return false;
        }

        static void ipAllocator() {
            static hard_limit = 5000;
            import core.sys.posix.unistd;
            uid_t euid, ruid;
            euid = geteuid();
            ruid = getuid();
            writeln("euid: ", euid, " ruid: ", ruid);
            while(true) {
                writeln("spawning receiver thread");
                receive((Tid requestThread, string uuid, string action) {
                        writeln("setting euid back to ", ruid);
                        seteuid(ruid);
                        if(getuid() != 0) {
                            writeln("wtf?");
                            return;
                        }
			import std.format, std.random;
			import std.array : array;
                        import std.range : generate, takeExactly;
                        import std.process;

			if(action == "create_nic") {
				int count = 0;
				while(true) {
					writeln("allocating for uuid: " ~ uuid, " try: ", count);
					count++;

					int[] arr = generate!(() => uniform(1, 253)).takeExactly(2).array;

					//ip addr show primary | grep 'inet' | cut --delimiter=" " -f6
					//ip link show up | grep 'link' | cut --delimiter=" " -f6

					string mainIP = format!"169.254.%s.%s"((4 * arr[0] + 1) / 256, (4 * arr[1] + 1) % 256);

					auto checkIfAddr = executeShell("ip addr show primary | grep 'inet' | cut --delimiter=\" \" -f6");
					if(checkIfAddr.status != 0) {
						assert(0, "cannot check what interfaces exist??");
					}
					string[] allIPs = checkIfAddr.output.split();
					if(allIPs.canFind(mainIP)) {
						continue;
					}

					string gatewayIP = format!"169.254.%s.%s"((4 * arr[0] + 2) / 256, (4 * arr[1] + 2) % 256);

					string macAddress = format!"02:FC:%02X:%02X:%02X:%02X"(uniform(0, 254), uniform(0, 254), uniform(0, 254), uniform(0, 254));
					auto checkMACAddr = executeShell("ip link show up | grep 'link' | cut --delimiter=\" \" -f6");
					if(checkMACAddr.status != 0) {
						assert(0, "cannot check what MACs exist???");
					}

					string[] allMACs = checkMACAddr.output.split();
					if(allMACs.canFind(macAddress)) {
						continue;
					}

					string ifaceName = uuid ~ "-iface";

					auto delIface = executeShell(escapeShellCommand("ip", "link", "del", ifaceName));
					if(delIface.status != 0) {
					    writeln("got non-0 exit code for deleting interface");
					    writeln(delIface.output);
					}

					auto addIface = executeShell(escapeShellCommand("ip", "tuntap", "add", "dev", ifaceName, "mode", "tap")); 
					if(addIface.status != 0) {
					    writeln("got non-0 exit code for creating interface");
					    writeln(addIface.output);
					    return;
					}

					auto modifySettings = executeShell(escapeShellCommand("sysctl", "-w", "net.ipv4.conf." ~ ifaceName ~ ".proxy_arp=1"));
					if(modifySettings.status != 0) {
					    writeln("got non-0 exit code for modifying sysctl");
					    writeln(modifySettings.output);
					    return;
					}
					auto modifySettings_2 = executeShell(escapeShellCommand("sysctl", "-w", "net.ipv4.conf." ~ ifaceName ~ ".disable_ipv6=1"));
					if(modifySettings_2.status != 0) {
					    writeln("got non-0 exit code for modifying sysctl 2");
					    writeln(modifySettings_2.output);
					}

					auto addAddress = executeShell(escapeShellCommand("ip", "addr", "add", gatewayIP ~ "/30", "dev", ifaceName));
					if(addAddress.status != 0) {
					    writeln("got non-0 exit code for adding address");
					    writeln(addAddress.output);
					    return;
					}
				
					// ip link set address 02:FC:00:FC:00:FC dev docker0
					auto setMAC = executeShell(escapeShellCommand("ip link set address", macAddress, "dev", ifaceName)); 
					auto setLinkUp = executeShell(escapeShellCommand("ip", "link", "set", "dev", ifaceName, "up"));

					auto addIPTableRoute_1 = executeShell(escapeShellCommand("iptables", "-t", "nat", "-A", "POSTROUTING", "-o", "wlp2s0", "-j", "MASQUERADE"));
					auto addIPTableRoute_2 = executeShell(escapeShellCommand("iptables", "-A", "FORWARD", "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"));
					auto addIPTableRoute_3 = executeShell(escapeShellCommand("iptables", "-A", "FORWARD", "-i", ifaceName, "-o", "wlp2s0", "-j", "ACCEPT"));

					writeln("set euid back to ", euid);

					seteuid(euid);

					send(requestThread, IPInfo(macAddress, mainIP, gatewayIP));
				}
			}
			else if(action == "delete_nic") {


			}
			else if(action == "update_nsg") {

			}
		});
            }
        }
    }

    shared class NICResource : Resource {
	private {
		string _private_ip;
		string _public_ip;
		string _mac;
		string _devName;
		SecurityPolicy _secpol;
		bool _inUse = false;
	}

	NetworkInterface getRepresentation() {
		useResource();

		NetworkInterface n = new NetworkInterface();
		n.secpol = cast(SecurityPolicy)_secpol;
		n.publicIp = _public_ip;
		n.privateIp = _private_ip;

		releaseResource();
		return n;
	}

	override string getClass() {
		return "NIC";
	}

	override string getStatus() {
		if(_mac == "") {
			return "NO_MAC";
		}

		if(_private_ip == "") {
			return "NO_PRIV_IP";
		}

		if(_public_ip == "") {
			return "NO_PUBLIC_IP";
		}

		if(!attached) {
			return "NOT_ATTACHED";
		}

		return "OK";
	}

	override bool destroy() {
		useResource();

		bool status = false;

		if(canDisconnect()) {
			status = true;
		}
		if(attached) {
			status = false;
		}

		releaseResource();
		return status;
	}

	override bool deploy() {
		useResource();

		import std.format : format;
		import std.random : uniform;
		send(cast(Tid)allocator, thisTid, cast(string)uuid);
		IPInfo info;
		receiveTimeout(dur!"seconds"(5), (IPInfo i) { writeln("received"); info = i; });

		releaseResource();
		return true;
	}

	override bool connect(ResourceIdentifier id) {
		bool status = false;
		useResource();
		if(!attached) {
			status = true;
		}

		releaseResource();
		return status;
	}

	override bool disconnect() {
		bool status = false;
		useResource();
		if(canDisconnect()) {
		
		}


		releaseResource();
		return status;
	}

	override bool canDisconnect() {
		if(_inUse) {
			return false;
		}

		return true;
	}

	Resource constructor(string uuid) {
		auto r = new shared NICResource();
		import core.sync.mutex;
		mtx = new shared Mutex();
		uuid = uuid;

		return cast(Resource)r;
	}

    }

    this() {
        allocator = spawn(&ipAllocator);
    }
    
}
