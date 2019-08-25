#!/usr/bin/rdmd
import std.stdio;
import core.sys.posix.unistd : geteuid;
import std.string;

void exec(string...)(string args) {
	import std.process;

	debug writefln("executing command with args: %s", args);
	debug writefln("%s", "/bin/bash -c \"" ~ escapeShellCommand(args) ~ "\"");
	auto _o = executeShell("/bin/bash -c \"" ~ escapeShellCommand(args) ~ "\"");

	if (_o.status != 0) {
		writefln("%s", _o.output);
	}

	assert(_o.status == 0, "Command did not return 0..");

	return;
}

void main(string[] args) {
	if (args.length == 1) {
		writeln("Usage: ", args[0], " [netns name]");
		return;
	}

	if (geteuid() != 0) {
		writeln("Script must be run as root.");
		return;
	}

	string netns_path = "/var/run/netns/" ~ args[1];
	import std.file;
	import std.process : executeShell;

	string eth = args[1] ~ "_eth";

	if (!exists(netns_path)) {
		writeln("netns must exist.");
		return;
	}

	{
		import std.regex;

		auto regex = ctRegex!(`(\S*): [\s\w\-=\d<,>]*\n[a-zA-Z::0-9 <>\s]*\s*ether ([0-9a-z:]*)`);
		auto _o = executeShell("ifconfig -a");
		auto matches = matchAll(_o.output, regex);
		bool ok = false;
		foreach (match; matches) {
			if (match[1] == eth) {
				ok = true;
			}
		}

		if (!ok) {
			writeln("Unable to find an interface associated with netns.");
			return;
		}
	}

	{
		auto grabIP = executeShell(
				"iptables -t nat -L PREROUTING | grep '" ~ args[1] ~ "' |  awk '{print $5}'");
		auto grabInternalIP = executeShell(
				"iptables -t nat -L PREROUTING | grep '" ~ args[1] ~ "' |  awk '{print $9}'");

		if (grabInternalIP.status == 0) {
			string ip = grabInternalIP.output.split('\n')[0].strip("to:");
			{
				import std.conv : to;

				string[] parts = ip.split('.');
				parts[3] = to!string(to!int(parts[3]) - 1);

				ip = parts[0] ~ "." ~ parts[1] ~ "." ~ parts[2] ~ "." ~ parts[3];
			}
			auto t = executeShell("ip addr del " ~ ip ~ "/30 dev vm_bridge");
		}

		if (grabIP.status == 0) {
			auto t = executeShell("ip addr del " ~ grabIP.output.split('\n')[0] ~ "/16 dev wlan0");
		}

		auto post = executeShell(
				"iptables -t nat -L POSTROUTING --line-number | grep '"
				~ args[1] ~ "' | awk '{print $1}'");
		auto pre = executeShell(
				"iptables -t nat -L PREROUTING --line-number | grep '"
				~ args[1] ~ "' | awk '{print $1}'");

		foreach (l; post.output.split('\n')) {
			if (l == "") {
				continue;
			}
			auto t = executeShell("iptables -t nat -D POSTROUTING 1");
		}

		foreach (l; pre.output.split('\n')) {
			if (l == "") {
				continue;
			}
			auto t = executeShell("iptables -t nat -D PREROUTING 1");
		}

	}

	exec("/usr/bin/ip", "netns", "del", args[1]);
	exec("/usr/bin/ip", "link", "del", "dev", eth);

}
