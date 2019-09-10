module cli;
import structs;
public import cli.orchestrator;
import std.stdio : writeln;

mixin Command!("helloWorld", 2,
(string[] args) {
	try { 
		writeln("Hello, ", args[1]);
	} catch(Exception e) {
		writeln("Exception: ", e.msg);
	}
});

mixin Command!("version", 1, 
(string[] args) {
	writeln(productString, " ", versionString);
});

mixin Command!("menuChange", 2,
(string[] args) {
	switch(args[1]) {
		case "list":
			writeln("menus: ", menus);
			return;
		case "vmm":
			assert(0, "unimplemented");
		case "orchestrator":
			currentMenu = orchestratorMenu;
			break;
		case "admin":
			assert(0, "unimplemented");
		case "node":
			assert(0, "unimplemented");
		case "agent":
			assert(0, "unimplemented");
		default:
			enforce(0, "expected vmm, orchestrator, admin, node, or agent");

	}
});

static menu_entry mainMenu = {
	name: "main",
	entries: [
	{
		name: "hello",
		usage: "(string msg)",
		ptr: &__helloWorld
	},
	{	
		name: "abc",
		usage: "(string msg)",
		ptr: &__helloWorld
	},
	{
		name: "menu",
		usage: "(string newMenu)",
		ptr: &__menuChange
	},
	{
		name: "version",
		usage: "()",
		ptr: &__version
	}]
};

