module scylla.core.kintsugi;
import std.stdio;
import scylla.core.server;
import scylla.core.firecracker;
import bap.models.vps;
import std.file;
import std.concurrency;
import std.process;
import firecracker_d.models.client_models;
import std.algorithm.searching;
import core.exception;

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

        bool canHandleVPS(VPS request) {
            int allocRAM = 0;
            int totalRAM = 0;
            import std.file, std.string;
            string _memInfo = cast(string)read("/proc/meminfo");
            string[] memInfo = _memInfo.split('\n');

            foreach(_v; servers.keys) {

            }
            return true;
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
                receive((Tid requestThread, string uuid) {
                        writeln("setting euid back to ", ruid);
                        seteuid(ruid);
                        if(getuid() != 0) {
                            writeln("wtf?");
                            return;
                        }
                        writeln("allocating for uuid: " ~ uuid);
                        int count = 0;
                        import std.format, std.random;
                        import std.array : array;
                        import std.range : generate, takeExactly;
                        import std.process;
                        int[] arr = generate!(() => uniform(1, 253)).takeExactly(2).array;
                        string mainIP = format!"169.254.%s.%s"((4 * arr[0] + 1) / 256, (4 * arr[1] + 1) % 256);
                        string gatewayIP = format!"169.254.%s.%s"((4 * arr[0] + 2) / 256, (4 * arr[1] + 2) % 256);
                        writeln(gatewayIP, " ", mainIP);
                        string macAddress = format!"02:FC:%02X:%02X:%02X:%02X"(uniform(0, 254), uniform(0, 254), uniform(0, 254), uniform(0, 254));
                        if(allocatedIPs.canFind(mainIP) || allocatedIPs.canFind(gatewayIP) || allocatedMACs.canFind(macAddress)) {
                            writeln("collision");
                        }

                        string ifaceName = uuid ~ "-iface";

                        auto delIface = executeShell(escapeShellCommand("ip", "link", "del", ifaceName));
                        if(delIface.status != 0) {
                            writeln("got non-0 exit code for deleting interface");
                            writeln(delIface.output);
                        }

                        //ip tuntap add dev "$TAP_DEV" mode tap
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
                        auto setLinkUp = executeShell(escapeShellCommand("ip", "link", "set", "dev", ifaceName, "up"));

                        /*
                           sudo iptables -t nat -A POSTROUTING -o $WIRELESS_DEVICE_NAME -j MASQUERADE
                            sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
                            sudo iptables -A FORWARD -i tap0 -o $WIRELESS_DEVICE_NAME -j ACCEPT
                        */
                        auto addIPTableRoute_1 = executeShell(escapeShellCommand("iptables", "-t", "nat", "-A", "POSTROUTING", "-o", "wlp2s0", "-j", "MASQUERADE"));
                        auto addIPTableRoute_2 = executeShell(escapeShellCommand("iptables", "-A", "FORWARD", "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"));
                        auto addIPTableRoute_3 = executeShell(escapeShellCommand("iptables", "-A", "FORWARD", "-i", ifaceName, "-o", "wlp2s0", "-j", "ACCEPT"));

                        writeln("set euid back to ", euid);

                        seteuid(euid);

                        send(requestThread, IPInfo(macAddress, mainIP, gatewayIP));

                });
            }
        }
    }

    void spawnVM(VPS server) {
        if(servers.keys.canFind(server.uuid)) {
            writeln("server already provisioned?");
        }
        else {
            
            if(server.state == VPS.State.provisioned) {
                writefln("VPS %s WAS IN A BAD STATE", server.uuid);
                return;
            }

            writeln("creating new firecracker instance");

            FirecrackerVM fcVM = new FirecrackerVM(server.uuid);
            writeln("asking for new ip");
            IPInfo serverIP = requestIP(server.uuid[0..5]);
            fcVM.allocatedIP(serverIP);

            writeln("got ip: ", serverIP.mainIP, " gateway: ", serverIP.gatewayIP);
            
            if(server.boot.bootArgs == "") {
                server.boot.bootArgs = "console=ttyS0 panic=1 pci=off reboot=k tsc=reliable quiet 8250.nr_uarts=0 ipv6.disable=1 init=/bin/systemd noapic"; 
            } 
            import std.format;
            server.boot.bootArgs = format!"%s ip=%s::%s:255.255.255.252::eth0:off"(server.boot.bootArgs, serverIP.gatewayIP, serverIP.mainIP);

            if(server.boot.kernelImagePath == "") {
                server.boot.kernelImagePath = "/srv/scylla/boot_images/generic/ubuntu";
            }

            if(server.drives.length == 0) {
                Drive d;
                d.driveID = "1";
                d.pathOnHost = "/srv/scylla/disk_images/generic/ubuntu";
                d.isRootDevice = true;
                d.isReadOnly = true;
                server.drives ~= d;
            }

            if(server.config.vcpuCount == 0) {
                server.config.vcpuCount = 1;
            }

            if(server.config.memSizeMib == 0) {
                server.config.memSizeMib = 512;
            }

            if(server.nics.length == 0) {
                NetworkInterface n;
                n.ifaceID = "1";
                n.guestMAC = serverIP.macAddress;
                n.hostDevName = server.uuid[0..5] ~ "-iface";
                server.nics ~= n;
            }

            fcVM.createFromVPS(server);

            servers[server.uuid] = fcVM; 
        }
    }

    string getInstanceState(string uuid) {
        string ret = "";
        if(vmExists(uuid)) {
            import core.exception;
            FirecrackerVM vm = servers[uuid];

            if(vm.isAlive()) {

                try {
                    if(vm.isRunning()) {
                        ret = "online";
                    }
                    else {
                        ret = "offline";
                    }
                }
                catch(InvalidMemoryOperationError) {
                    ret = "offline";
                }
                catch(Exception) {
                    ret = "offline";
                }
            }

        }
        return ret;
    }

    IPInfo getIPAddress(string uuid) {
        IPInfo ret;
        if(vmExists(uuid)) {
            FirecrackerVM vm = servers[uuid];
            return vm.allocatedIP();
        }
        return ret;
    }


    bool startVM(string uuid) {
        writeln("got start request for uuid: '" ~ uuid ~ "'");
        if(vmAlive(uuid)) {
            writeln("vm exists, pulling it from the array");
            FirecrackerVM vm = servers[uuid];
            try {
                vm.start();
                writeln("sending start request to firecracker..");
            }
            catch(FirecrackerException e) {
                writeln("caught a firecracker exception..");
                return false;
            }
            return true;
        }
        else {
            FirecrackerVM vm = servers[uuid];
            writeln("vm potentially exists, but we're just recreating it to be sure..");
            vm.recreate();
            writeln("then we're sending a start command");
            vm.start();
            return true;
        }
    }

    bool gracefulShutdown(string uuid) {
        if(vmAlive(uuid)) {
            FirecrackerVM vm = servers[uuid];
            vm.shutdown();
            return true;
        }
        return false;
    }

    bool reboot(string uuid) {
        if(vmAlive(uuid)) {
            FirecrackerVM vm = servers[uuid];
            vm.reboot();
            return true;
        }
        return false;
    }

    bool halt(string uuid) {
        if(vmAlive(uuid)) {
            FirecrackerVM vm = servers[uuid];
            vm.stop();
            return true;
        }
        return false;
    }

    string[] getLogs(string uuid) {
        if(vmAlive(uuid)) {
            FirecrackerVM vm = servers[uuid];
            return vm.getLogs();
        }
        return [""];
    }


    IPInfo requestIP(string uuid) {
        IPInfo ret;
        import core.exception, core.time;
        try {
            send(allocator, thisTid, uuid);
            writeln("sent to allocator thread");
            receiveTimeout(dur!"seconds"(5), (IPInfo i) { writeln("received"); ret = i; });
            writeln("received");
        } catch(Exception e) {
            writeln("GOT EXCEPTION WHEN REQUESTING IP");
        }
        return ret;
    }

    this() {
        allocator = spawn(&ipAllocator);
    }
    
}
