module valkyrie.root.rootdriver;
import std.algorithm.searching;
import core.thread;
import core.time;
import dproto.dproto;
import zmqd;
import bap.core.utils;
import valkyrie.models.nic;

void exec(string...)(string args)
{
    import std.process;

    writefln("executing command with args: %s", args);
    writefln("%s", "/bin/bash -c \"" ~ escapeShellCommand(args) ~ "\"");
    auto _o = executeShell("/bin/bash -c \"" ~ escapeShellCommand(args) ~ "\"");

    if (_o.status != 0)
    {
        writefln("%s", _o.output);
    }
    assert(_o.status == 0, "Command did not return 0..");

    return;
}

class RootDriver
{
    //the only class which should ever have root.
private:
    string[] allocatedIPRange;
    string[] allocatedMACRange;
    string[string] nicToNSTable;

    bool allocateNewNIC(ResourceIdentifier id)
    {
        return false;
    }

    bool dhcpRequest(string bindIface)
    {
        return false;
    }

    bool assignNICProperties(string nic, string ip, string mac)
    {
        return false;
    }

    bool addNSGInRule(SecurityInPolicy pol)
    {
        return false;
    }

    bool addNSGOutRule(SecurityOutPolicy pol)
    {
        return false;
    }

public:
    static void eventHandler()
    {
        auto broker = Socket(SocketType.pull);
        broker.bind("inproc://rootdriver");
        log(LogLevel.DEBUG, "rootdriver binded");

        bool run = false;
        while (run)
        {
            auto frame = Frame();
            auto r = broker.tryReceive(frame);
            if (r[1])
            {
                //					RootDriverEvt evt = RootDriverEvt(frame.data);

                log(LogLevel.DEBUG, "rootdriver received frame");
            }

            Thread.sleep(1.msecs);
        }
    }

    this()
    {
        auto thread = new Thread(&eventHandler);
        thread.isDaemon(true);
        thread.start();
    }
}
