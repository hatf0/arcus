import std.stdio;
import zephyr.core.server;
import vibe.d;

void main()
{
    import core.sys.posix.unistd, std.process;

    uid_t ruid = getuid();

    assert(ruid == 0, "zephyr must be run as root");

    import std.file;
    import core.sys.posix.sys.stat, std.conv, std.string;

    if (!exists("/etc/zephyr"))
    {
        std.file.mkdir("/etc/zephyr");
        executeShell("chmod -R 755 /etc/zephyr");
        executeShell("chown -R nobody:kvm /etc/zephyr");
    }

    ZephyrServer s = new ZephyrServer("/etc/zephyr/config.json");

    lowerPrivileges("nobody", "kvm");
    s.startListener();

    runApplication();
}
