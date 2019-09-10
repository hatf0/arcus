import std.stdio;
import deimos.linenoise;
import structs;
import cli;
import std.string;

extern(C) void completion(const char *buf, linenoiseCompletions *lc) {
	import std.algorithm.sorting;
	import std.algorithm.iteration;
	string[] array;
	string _buf = fromStringz(cast(char*)buf).idup; 
	foreach(m; currentMenu.entries) {
		if(m.name.length >= _buf.length) {
			foreach(i, _m; _buf) {
				if(_m != m.name[i]) {
					goto next;
				}
			}
			linenoiseAddCompletion(lc, toStringz(m.name));
			array ~= m.name;
		next:
		}
	}

	import std.algorithm.searching;
	 
}
	
int main(string[] args) {
	import core.stdc.string, core.stdc.stdlib;
	import std.path;

	currentMenu = mainMenu;

	linenoiseSetCompletionCallback(&completion);

	const char* history = expandTilde("~/.arcus_history").toStringz;

	char* line;

	linenoiseHistoryLoad(history);

	while((line = linenoise("cli> ")) !is null) {
		string _line = fromStringz(line).idup;
		
		/* Do something with the string. */
		if (line[0] != '\0' && line[0] != '/') {
			string[] _args = _line.split(' ');

			writeln("call method: ", _args[0]); 
			if(_args.length > 1) {
				writeln("with args: ", _args);
			}

			bool found = false;

			if(_args[0] == "quit") {
				writeln("goodbye");
				return 0;
			}
			
			if(_args[0] == "help") {
				writeln("menu: ", currentMenu.name);
				writeln("commands:");
				foreach(c; currentMenu.entries) {
					writeln("\t", c.name, " ", c.usage);
				}
				continue;
			}

			foreach(c; currentMenu.entries) {
				if(c.name == _args[0]) {
					try { 
						c.ptr(_args);
					} catch(Exception e) {
						writeln("Command failed. Reason: ", e.msg);
					}

					found = true;
					break;
				}
			}

			if(!found) {
				foreach(c; mainMenu.entries) {
					if(c.name == _args[0]) {
						try {
							c.ptr(_args);
						} catch(Exception e) {
							writeln("Command failed. Reason: ", e.msg);
						}

						found = true;
						break;
					}
				}
			}

			if(!found) {
				writeln("no such command");
			}
			linenoiseHistoryAdd(line);
		}
		free(line);
	}

	linenoiseHistorySave(history);

	return 0;
}

