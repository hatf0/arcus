#!/usr/bin/rdmd
import std.stdio;
import core.sys.posix.unistd : geteuid;

/*
   Helper function
*/

string ipArrayToString(int[4] ip) {
	import std.format;
	return format!"%d.%d.%d.%d"(ip[0], ip[1], ip[2], ip[3]);
}

/*
   Usage case for this template: any program that returns 0 on success.
   This will assert if the program does not return 0..
*/

void exec(string...)(string args) {
	import std.process;

	debug writefln("executing command with args: %s", args);
	debug writefln("%s", "/bin/bash -c \"" ~ escapeShellCommand(args) ~ "\"");
	auto _o = executeShell("/bin/bash -c \"" ~ escapeShellCommand(args) ~ "\"");

	if(_o.status != 0) {
		writefln("%s", _o.output);
	}

	assert(_o.status == 0, "Command did not return 0..");

	return;
}
	

void main(string[] args) {
	if(args.length == 1) {
		writeln("Usage: ", args[0], " [netns name]");
		return;
	}

	if(geteuid() != 0) {
		writeln("Program must be run as root.");
		return;
	}

	string netns_path = "/var/run/netns/" ~ args[1];
	import std.file;

	import std.process : executeShell;

	if(exists(netns_path)) {
		writeln("netns already exists.");
		return;
	}

	//change scope for executeShell, we don't need the output
	{
		auto _o = executeShell("brctl show vm_bridge");
	
		if(_o.status != 0) {
			exec("brctl", "addbr", "vm_bridge");
			exec("iptables", "-t", "nat", "-A", "POSTROUTING", "-s", "172.0.0.0/8", "-j", "MASQUERADE");
			exec("sysctl", "-w", "net.ipv4.ip_forward=1");
			//ip addr add 172.0.0.1/24 brd + dev vm_bridge
		}
	}

	//again, output is discarded
	{
		import std.regex;
		auto regex = ctRegex!(`(\S*): [\s\w\-=\d<,>]*\n[a-zA-Z::0-9 <>\s]*\s*ether ([0-9a-z:]*)`);
		auto _o = executeShell("ifconfig -a");
		auto matches = matchAll(_o.output, regex);
		foreach(match; matches) {
			writefln("matched iface %s with mac %s", match[1], match[2]);
		}
		
	}


	// ALL PRIVATE IPS WILL BE IN THE 172.x.x.x RANGE
	// THIS SHOULD BE NETWORK HETEROGENOUS BUT THERE MAY BE EDGE CASES THAT I HAVE NOT CONSIDERED
	//0 out 1 in
	// MODIFY THE SOURCE IP TO REFLECT THE PUBLIC IP
	//iptables -t nat -A POSTROUTING -s (private ip) -j SNAT --to-source 10.0.0.160
	// MODIFY THE DESTINATION IP TO REFLECT THE PRIVATE IP
	//iptables -t nat -A PREROUTING -p tcp --dport 1111 -j DNAT --to-destination 2.2.2.2:1111


	//_sveth is the interface which is inside of the network namespace
	//_eth is the interface which is on the host side..

	// traffic flow
	//			
	//    (bgp somewhere in here)   
	//  the internet   <- external interface (router, NAT is performed)
	//			      |
	//                        vm_bridge
	//			      |    (namespaced)
	//			    _eth <--------------> _sveth
	//
	// ** ASSUME ALL PRIVATE IPS ARE BEHIND A NAMESPACE!! **							
	// given _eth's public ip is 1.1.1.5, and it's private ip is 172.0.0.5 
	//
	// router's purpose is to:
	//	- receive incoming traffic TO a certain IP (1.1.1.5)
	//	- forward said traffic to the respective _eth interface (send transparently)
	//	- receive any traffic from _eth interface that is directed to the web, and set the origin IP to 1.1.1.5

	string[2] veth_pair = [args[1] ~ "_sveth", args[1] ~ "_eth"];

	writefln("adding netns %s", args[1]);

	exec("/usr/bin/ip", "netns", "add", args[1]);

	exec("/usr/bin/ip", "link", "add", veth_pair[0], "type", "veth", "peer", "name", veth_pair[1]);

	exec("brctl", "addif", "vm_bridge", veth_pair[1]);

	exec("/usr/bin/ip", "link", "set", "dev", veth_pair[0], "netns", args[1]);


	auto _o = executeShell("awk '/32 host/ { print f } {f = $2}' <<< cat /proc/net/fib_trie"); 


	string[] bad_ip_list;
	import std.string : split;
	foreach(l; _o.output.split()) {
		import std.conv : to;
		string[] parts = l.split(".");

		if(parts[0] == "172") {
			bad_ip_list ~= l;
			writefln("marked ip %s bad", bad_ip_list[$ - 1]);
			if(parts[3] != "1" && parts[3] != "0") {
				parts[3] = to!string(to!int(parts[3]) - 1);
				bad_ip_list ~= parts[0] ~ "." ~ parts[1] ~ "." ~ parts[2] ~ "." ~ parts[3];
				writefln("marked gateway %s bad", parts[0] ~ "." ~ parts[1] ~ "." ~ parts[2] ~ "." ~ parts[3]);
			}
			else {
				parts[3] = to!string(to!int(parts[3]) + 1);
				bad_ip_list ~= parts[0] ~ "." ~ parts[1] ~ "." ~ parts[2] ~ "." ~ parts[3];
				writefln("marked gateway %s bad", parts[0] ~ "." ~ parts[1] ~ "." ~ parts[2] ~ "." ~ parts[3]);
			}


		}
	}

	int[4] ip = [172, 0, 0, 0];
	for(int a = 0; a < 255; a++) {
		for(int b = 0; b < 255; b++) {
			for(int c = 0; c < 255; c += 4) {
				import std.format;
				string ip_string = format!"%d.%d.%d.%d"(ip[0], a, b, c + 1);
				
				import std.algorithm.searching : canFind;

				if(!bad_ip_list.canFind(ip_string)) {
					ip_string = format!"%d.%d.%d.%d"(ip[0], a, b, c + 2);
					if(!bad_ip_list.canFind(ip_string)) {
						ip[1] = a;
						ip[2] = b;
						ip[3] = c + 1;
						writefln("picked an ip: %s", ipArrayToString(ip));
						goto done;
					}
					else {
						writefln("found a second bad ip: %s", ip_string);
					}
				}
				else {
					writefln("found a bad ip: %s", ip_string);
				}

			}
		}
	}

done:
	int[4] ip_gateway = ip.dup;
	ip[3] += 1;

	//THIS WILL ACTUALLY BE PROPERLY DONE, THIS IS JUST A DIRTY HACK!!
	int[4] public_ip = [10, 0, 1, 0];
	for(int c = 1; c < 255; c++) {
		for(int d = 1; c < 255; c++) {
			import std.format;
			string ip_string = format!"%d.%d.%d.%d"(public_ip[0], public_ip[1], c, d);
				
			import std.algorithm.searching : canFind;

			if(!bad_ip_list.canFind(ip_string)) {
				public_ip[2] = c;
				public_ip[3] = d;
				goto public_ip_done;
			}
			else {
				writefln("found a bad ip: %s", ip_string);
			}
		}
	}
public_ip_done:

	/* these will have to be executed inside of the container */
	exec("/usr/bin/ip", "netns","exec", args[1], "ifconfig", veth_pair[0], ipArrayToString(ip) ~ "/30"); 
	exec("/usr/bin/ip", "netns", "exec", args[1], "ip", "route", "add", "default", "via", ipArrayToString(ip_gateway));
	/* they're just executed inside of the network namespace for clarity sake */

	exec("/usr/bin/ip", "addr", "add", ipArrayToString(ip_gateway) ~ "/30", "brd", "+", "dev", "vm_bridge");

	//sudo iptables -t nat -A POSTROUTING -s 172.0.0.6 -j SNAT --to-source 10.0.1.10
	//sudo iptables -t nat -A PREROUTING -j DNAT -d 10.0.1.10 --to-destination 172.0.0.6

	exec("/usr/bin/ip", "addr", "add", "dev", "wlan0", ipArrayToString(public_ip) ~ "/16"); 
	// forward all requests from the private ip to the public ip

	exec("/usr/bin/iptables", "-t", "nat", "-A", "POSTROUTING", "-s", ipArrayToString(ip), "-j", "SNAT", "--to-source", ipArrayToString(public_ip), "-m", "comment", "--comment", "\"" ~ args[1] ~ "\"");

	// forward all inbound requests for the public ip to the private ip
	exec("/usr/bin/iptables", "-t", "nat", "-A", "PREROUTING", "-j", "DNAT", "-d", ipArrayToString(public_ip), "--to-destination", ipArrayToString(ip), "-m", "comment", "--comment", "\"" ~ args[1] ~ "\"");

	exec("/usr/bin/ip", "link", "set", veth_pair[1], "up"); 


	writeln("gateway: ", ipArrayToString(ip_gateway) ~ "/30", " ip: ", ipArrayToString(ip) ~ "/30");
	writeln("public ip: ", ipArrayToString(public_ip) ~ "/16");

	/*
		ip link add "$NETNS_ETHIN" type veth peer name "$NETNS_ETHOUT"
		ip link set dev "$NETNS_ETHOUT" netns "$1"
		ip netns exec db ifconfig "$NETNS_ETHOUT" 172.0.0.2/30
		ifconfig "$NETNS_ETHIN" 172.0.0.1/30
	*/



}
	

/*
if [ -z $1 ]; then
	echo "Usage: $0 [netns name]"
	exit
fi

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root."
	exit 1
fi

NETNS_PATH = "/var/run/netns/$1" 
if test -f "$NETNS_PATH"; then
	echo "Your NETNS should not exist."
	exit 1
fi

echo "Creating veth pair.."
NETNS_ETHOUT = "$1_sveth"
NETNS_ETHIN = "$1_veth" 

*/



	
