		void replThread() {
			import std.string;
			string line;
			string context = "main";
			while ((line = readln()) !is null) {
				string[] parts = line.strip().split(' ');
				if(parts[0] == "help") {
					logInfo("repl", "Arcus vDEV");
					logInfo("repl", "Available commands:");
					if(context == "main") {
						logInfo("repl", "help - This command");
						logInfo("repl", "--- Resource Manipulation ---");
						logInfo("repl", "get - Get an arbitrary resource");
						logInfo("repl", "new - Create a new resource.");
						logInfo("repl", "delete - Delete a resource given it's UUID.");
						logInfo("repl", "set - Set a resource's properties, given it's UUID");
						logInfo("repl", "deploy - Deploy a resource");
						logInfo("repl", "--- Orchestrator Controls ---");
						logInfo("repl", "quit - Quit the orchestrator.");
						logInfo("repl", "onboard - Initiate the onboarding sequence.");
						logInfo("repl", "status - Get the current status of the orchestrator.");
						logInfo("repl", "--- Contextual Commands ---");
						logInfo("repl", "menu - Switch to a different context.");
						logInfo("repl", "\tAvailable contexts: firecracker, main");
					}
					else if(context == "firecracker") {
						logInfo("repl", "vm - Perform actions on a virtual machine");
						logInfo("repl", "\tActions that you are able to perform:");
						logInfo("repl", "\tstart, stop, restart, reboot, halt");
						logInfo("repl", "disk - Perform actions on a disk.");
						logInfo("repl", "\tActions that you are able to perform:");
						logInfo("repl", "\tresize, restore");
						logInfo("repl", "nic - Perform actions on a network interface.");
						logInfo("repl", "\tActions that you are able to perform:");
						logInfo("repl", "\tset_namespace, renew_dhcp, release_dhcp");
						logInfo("repl", "agent - Perform actions inside of a virtual machine.");
						logInfo("repl", "\tActions that you are able to perform:");
						logInfo("repl", "\treset_ssh, set_password, exec");
						logInfo("repl", "Note: all commands from the previous context are available.");
					}
					goto cursor;
				}
				else if(parts[0] == "new") {
					if(parts.length == 1) {
						logError("repl", "Expected a class name for the new resource.");
						goto cursor;
					}

					if(g_ResourceManager.isValidClass(parts[1])) {
						auto res = g_ResourceManager.instantiateResource(parts[1]);
						logInfo("repl", "Instantiated an resource with the class: " ~ parts[1]);
						logInfo("repl", "UUID: " ~ res.uuid);
					}
				}
				else if(parts[0] == "delete") {
					if(parts.length == 1) {
						logInfo("repl", "Usage: delete (uuid)");
						goto cursor;
					}

					string uuid = parts[1];

					if(g_ResourceManager.destroyResource(id("example", uuid))) {
						logInfo("repl", "Deleted UUID: " ~ uuid ~ " successfully.");
					}
					else {
						logError("repl", "Was not able to delete object successfully.");
					}

				}
				else if(parts[0] == "get") {
					if(parts.length == 1) {
						logError("repl", "Expected a token in the second field.");
						goto cursor;
					}

					if(parts[1] == "all") {
						string[] resources = g_ResourceManager.getAllResources();

						import std.conv : to;
						string filter = "";
						int count = 0;
						if(parts.length == 3) {
							filter = parts[2];
						}

						if(filter == "classes") {
							foreach(i, r; g_ResourceManager.getAllResourceClasses()) {
								logInfo("repl", "Class #" ~ to!string(i) ~ ": " ~ r); 
								count++;
							}

							logInfo("repl", "Total classes: " ~ to!string(count));
							goto cursor;
						}



						foreach(r; resources) {
							shared(Resource) res = g_ResourceManager.getResource(id("example", r));
							if(!(res is null)) {
								string rClass = res.getClass();
								if(filter != "" && rClass == filter) {
									logInfo("repl", r ~ " is a " ~ rClass); 
									count++;
								}
								else if(filter == "") {
									logInfo("repl", r ~ " is a " ~ rClass);
									count++;
								}
							}

						}
						logInfo("repl", "Found " ~ to!string(resources.length) ~ " resource(s)."); 

					}
					else {
						shared(Resource) _res = g_ResourceManager.getResource(id("example", parts[1]));

						if(parts.length != 3) {
							logError("repl", "Usage: get (uuid) (variable)");
							goto cursor;
						}

						if(_res !is null) {
							string uuid = parts[1];
							string variable = parts[2];
							string[] list;
							bool found = false;
							file_entry entry;
							foreach(f; _res.getFiles) {
								list ~= f.name;
								if(f.name == variable) {
									found = true;
									entry = f;
								}
							}

							if(!found || variable == "vars") {
								if(!found && variable != "vars") {
									logError("repl", "Variable does not exist.");
								}
								logInfo("repl", "Available variables: ");
								foreach(n; list) {
									logInfo("repl", "\t" ~ n);
								}
								goto cursor;
							}

							Variant v = _res.storage[variable];
							logInfo("repl", "Value: " ~ v.toString());




						}
					}
				}
				else if(parts[0] == "set") {
					if(parts.length != 4) {
						logInfo("repl", "Usage: set (uuid) (variable) (value)");
						goto cursor;
					}

					string uuid = parts[1];
					string variable = parts[2];
					string value = parts[3]; 

					shared(Resource) _res = g_ResourceManager.getResource(id("example", uuid));
					if(_res !is null) {
						bool found = false;
						string[] list;
						file_entry entry;
						foreach(f; _res.getFiles) {
							list ~= f.name;
							if(f.name == variable) {
								found = true;
								entry = f;
							}
						}

						if(!found) {
							logError("repl", "Variable does not exist.");
							logError("repl", "Available variables: ");
							foreach(n; list) {
								logError("repl", "\t" ~ n);
							}
							goto cursor;
						}

						import std.conv : to;
						Variant a = 0;
						try {
							if(entry.type == file_entry.types.typeFloat) {
								a = to!float(value);
							}
							else if(entry.type == file_entry.types.typeString) {
								a = value;
							}
							else if(entry.type == file_entry.types.typeInt64) {
								a = to!long(value);
							}
							else if(entry.type == file_entry.types.typeInt) {
								a = to!int(value);
							}
							else if(entry.type == file_entry.types.typeBool) {
								a = to!bool(value);
							}
							else if(entry.type == file_entry.types.typeRaw) {
								logError("repl", "variables with the type 'raw' cannot be set on the commandline.");
								goto cursor;
							}

							_res.storage[variable] = a;
						} catch(Exception e) {
							logError("repl", "could not set variable, wrong type");
							writeln(e.msg);
							goto cursor;
						}

						logInfo("repl", "Updated variable.");
					}
					else {
						logError("repl", "Resource does not exist.");
						goto cursor;
					}

				}
				else if(parts[0] == "quit") {
					import vibe.core.core;
					logInfo("repl", "Goodbye");
					exitEventLoop(true);
				}
				else if(parts[0] == "deploy") {
					if(parts.length == 1) {
						logError("repl", "Expected a resource UUID.");
						goto cursor;
					}

					string uuid = parts[1];
					shared(Resource) _res = g_ResourceManager.getResource(id("example", uuid));
					_res.useResource();
					{
						Resource res = cast(Resource)_res;
						_res.deploy();
					}
					_res.releaseResource();

				}
				else if(parts[0] == "onboard") {
					logInfo("repl", "Unimplemented..");
				}
				else if(parts[0] == "menu") {
					if(parts.length != 2) {
						logError("repl", "Expected a menu to switch to.");
						logError("repl", "Available menus are: 'firecracker', 'main'");
						goto cursor;
					}

					if(parts[1] == "firecracker" || parts[1] == "main") {
						context = parts[1];
						logInfo("repl", "Switched to " ~ context ~ ".");
						goto cursor;
					}

				}
				else {
					logError("repl", "Unrecognized command.");
				}
cursor:
				write(context, " > ");
			}
		}

