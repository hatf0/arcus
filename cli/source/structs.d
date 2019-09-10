module structs;
public import std.exception : enforce;

static string productString = "Arcus/CLI";
static string versionString = "v0.0.1 PreAlpha";
static string[] menus = ["orchestrator", "vmm", "admin", "node", "agent"];
static menu_entry currentMenu;

mixin template Command(string name, int minArgs, void function(string[] args) func) {
	import std.conv : to;
	mixin("
		void __" ~ name ~ "(string[] args) 
		in {
			enforce(args.length >= " ~ to!string(minArgs) ~ ", \"not enough arguments\");
		}
		do {
			func(args);
		}
	");
}

struct cmd_entry {
	string name;
	string usage;
	void function(string[] args) ptr;	
}

struct menu_entry {
	string name;
	cmd_entry[] entries;
}


