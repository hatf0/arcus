import vibe.vibe;
import std.stdio;
import bap.core.node;
import bap.model;
import scylla.core.server.server;
import scylla.core.server.kintsugi;
import bap.core.resource_manager;
extern(C) __gshared string[] rt_options = [ "gcopt=initReserve:50 profile:1" ];

void main()
{
    import core.sys.posix.unistd, std.process;
    uid_t ruid = getuid();

    assert(ruid == 0, "scylla must be run as root");

    import std.file;

    import core.sys.posix.sys.stat, std.conv, std.string;
    if(!exists("/etc/scylla")) {
        std.file.mkdir("/etc/scylla");
	std.file.mkdir("/etc/scylla/backups");
        executeShell("chmod -R 755 /etc/scylla");
        executeShell("chown -R nobody:kvm /etc/scylla"); 
    }

    // all classes will be backed up to this path

    filePath = "/etc/scylla/mounts";
    backupPath = "/etc/scylla/backups";

    if(!exists("/srv/scylla")) {
        std.file.mkdir("/srv/scylla");
        std.file.mkdir("/srv/scylla/boot_images");
        std.file.mkdir("/srv/scylla/disk_images");
        executeShell("chmod -R 755 /srv/scylla");
        executeShell("chown -R nobody:kvm /srv/scylla"); 
    }
    /* 
       the g_ResourceManager persists for the lifetime of the app.. ensure it's created before something that's destroyed fast
     */

    g_ResourceManager = new ResourceManager();
    mixin ResourceInjector!("LogEngine", "bap.core.logger");

    foreach (string name; dirEntries(backupPath, SpanMode.shallow)) {
	    import std.path : buildPath;
	    ubyte[] data = cast(ubyte[])read(buildPath(backupPath, name));
	    g_ResourceManager.instantiateFromBackup(data);
	    remove(buildPath(backupPath, name));
    }

    ScyllaServer s = new ScyllaServer("/etc/scylla/config.json");

    s.startListener();
    runApplication();

    g_ResourceManager.cleanup();

    import core.memory;
    GC.disable;

}
