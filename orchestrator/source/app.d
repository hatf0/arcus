import vibe.vibe;
import std.stdio;
import bap.core.node;
import bap.model;
import scylla.core.server.server;
import scylla.core.server.kintsugi;

void main()
{
    import core.sys.posix.unistd, std.process;
    uid_t ruid = getuid();

    assert(ruid == 0, "scylla must be run as root");
    import std.file;

    /* Ensure that a 'kvm' group actually exists */
    auto n = slurp!(string, string, int, string)("/etc/group", "%s:%s:%d:%s");
    bool kvmGroup = false;
    foreach(k; n) {
        if(k[0] == "kvm") {
            kvmGroup = true;
            break;
        }
    }
    assert(kvmGroup, "expected kvm group to exist");

    import core.sys.posix.sys.stat, std.conv, std.string;
    if(!exists("/etc/scylla")) {
        std.file.mkdir("/etc/scylla");
        executeShell("chmod -R 755 /etc/scylla");
        executeShell("chown -R nobody:kvm /etc/scylla"); 
    }

    if(!exists("/srv/scylla")) {
        std.file.mkdir("/srv/scylla");
        std.file.mkdir("/srv/scylla/boot_images");
        std.file.mkdir("/srv/scylla/disk_images");
        executeShell("chmod -R 755 /srv/scylla");
        executeShell("chown -R nobody:kvm /srv/scylla"); 
    }

    ScyllaServer s = new ScyllaServer("/etc/scylla/config.json");

    s.startListener();
    runApplication();
}
