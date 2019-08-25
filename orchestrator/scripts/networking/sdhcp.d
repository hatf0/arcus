module sdhcp;
import std.socket;
import std.stdio;
import std.string;
import defines;
import core.thread;
import core.time;
import std.concurrency;
import std.typecons : Tuple;

__gshared int level = Error;

enum
{
    Debug,
    Info,
    Warning,
    Error
}

void printVerbose(A, T...)(A logLevel, T t)
{
    import std.stdio;

    string prefix = "";
    string suffix = "\u001b[0m";
    if (logLevel >= level)
    {
        switch (logLevel)
        {
        case Error:
            prefix = "\u001b[31;1m";
            break;
        case Warning:
            prefix = "\u001b[33;1m";
            break;
        case Info:
            prefix = "\u001b[36;1m";
            break;
        case Debug:
            prefix = "\u001b[38;5;245m";
            break;
        default:
            break;
        }

        writeln(prefix, t, suffix);
    }
}

long unixTime()
{
    import std.datetime;

    SysTime today = Clock.currTime();
    return today.toUnixTime();
}

void writeHex(ubyte[] array)
{
    string l;
    foreach (i, x; array)
    {
        l ~= format!"%x"(x);
        if (i != (array.length - 1))
        {
            l ~= " ";
        }
    }

    writeln(l);
}

static void recvLoop(int _sock, Tid ownerTid)
{
    Socket sock = new Socket(cast(socket_t) _sock, AddressFamily.INET);
    bool run = true;
    while (run)
    {
        if (receiveTimeout(dur!"msecs"(100), (bool t) { run = t; }))
        {
            break;
        }

        ubyte[300] buf;

        ubyte type;
        ptrdiff_t len = sock.receive(cast(void[]) buf);

        if (len == 0)
        {
            continue;
        }

        if (len == Socket.ERROR)
        {
            continue;
        }

        printVerbose(Debug, "read: ", len);

        bootp* s = cast(bootp*) buf.ptr;

        if (s == null)
        {
            continue;
        }

        optget(s.optdata, &type, ODtype, 1);

        if (type == DHCPoffer || type == DHCPack || type == DHCPnak || type == Timeout0)
        {
            //send this shit off
            send(ownerTid, type, buf);
        }
    }
}

class dhcpclient
{
private:
    Socket sock;
    Tid recvThread;
    static ubyte[] magic = [99, 130, 83, 99];
    string bindiface, iface;

    alias DHCPInfo = Tuple!(bool, "status", dsin_addr, "ip", dsin_addr,
            "gateway", dsin_addr, "mask");
    bootp* bp;
    void dhcpsend(int type, int how)
    {
        ubyte[] ip;
        ubyte[] p;
        ubyte* _p;

        bp = new bootp();
        //yikes
        hnput(&bp.op, Bootrequest, 1);
        hnput(&bp.htype, 1, 1);
        hnput(&bp.hlen, 6, 1);
        bp.xid = _config.xid.dup;
        hnput(bp.flags.ptr, Fbroadcast, bp.flags.length);
        hnput(bp.secs.ptr, cast(uint)(unixTime() - _config.starttime), bp.secs.sizeof);
        bp.magic = magic;
        bp.chaddr = _config.hwaddr;
        p = bp.optdata;
        _p = p.ptr;
        p = hnoptput(p, ODtype, type, 1);
        p = optput(p, ODclientid, cast(ubyte[]) _config.cid);
        if (_config.hostname.length > 65)
        {
            _config.hostname = _config.hostname[0 .. 65];
        }

        p = optput(p, OBhostname, cast(ubyte[])(_config.hostname.dup) ~ '\0');

        switch (type)
        {
        case DHCPdiscover:
            break;
        case DHCPrelease:
            bp.ciaddr = _sav.client;
            goto case DHCPrequest; //reduce code reuse :)
        case DHCPrequest:
            p = optput(p, ODipaddr, _sav.client);
            p = optput(p, ODserverid, _sav.server);
            break;
        default:
            break;
        }

        p[0] = OBend;

        int buf_len = cast(int)((312 - 4) - p.length);

        printVerbose(Debug, "moving window: ", p);
        printVerbose(Debug, "buffer: ", _p[0 .. (312 - 4)]);
        printVerbose(Debug, "length: ", buf_len);
        printVerbose(Debug, "data: ", _p[0 .. buf_len]);
        //		debug writeln("moving window: ", p);
        //		debug writeln("buffer: ", _p[0..(312 - 4)]);
        //		debug writeln("length?: ", buf_len);
        //		debug writeln("data: ", _p[0..buf_len]);
        bp.optdata = _p[0 .. (312 - 4)];

        // HACK
        ubyte[] buf = cast(ubyte[]) bp[0 .. 1];
        sock.sendTo(buf, new InternetAddress("255.255.255.255", 67));
    }

public:
    struct config
    {
        ubyte[4] xid;
        ubyte[16] hwaddr;
        string hostname;
        long starttime;
        string ifname = "eth0";
        byte[16] cid;
        string program;
        int sock;
        int[3] timers;
    }

    config _config;

    struct sav
    {
        ubyte[4] server;
        ubyte[4] client;
        ubyte[4] mask;
        ubyte[4] router;
        ubyte[4] dns;
    }

    sav _sav;

    struct flags
    {
        bool dns = false;
        bool ip = true;
        bool background = false;
    }

    flags _flags;

    DHCPInfo dhcpRequest()
    {
        import std.variant : Variant;

        bool run = true;
        bool status = false;
        dsin_addr ip;
        dsin_addr gateway;
        dsin_addr mask;

        DHCPInfo d;
        while (run)
        {
            dhcpsend(DHCPdiscover, Broadcast);
            receiveTimeout(dur!"msecs"(100), (Variant v) {
                assert(v.convertsTo!(Tuple!(ubyte, ubyte[300]))());

                auto t = v.peek!(Tuple!(ubyte, ubyte[300]));

                auto type = t.expand[0];

                ubyte[300] bps = t.expand[1];

                bootp* p = cast(bootp*) bps.ptr;
                if (type == DHCPoffer)
                {
                    _sav.client = p.yiaddr.dup;
                    optget(p.optdata, _sav.server.ptr, ODserverid, 4);
                    dhcpsend(DHCPrequest, Broadcast);
                    writeln("sending request");
                }

                if (type == DHCPack)
                {
                    writeln("got an ACK");
                    uint renewalTime, rebindingTime, lease;
                    optget(p.optdata, _sav.mask.ptr, OBmask, 4);
                    optget(p.optdata, _sav.router.ptr, OBrouter, 4);
                    optget(p.optdata, _sav.dns.ptr, OBdnsserver, 4);
                    optget(p.optdata, cast(ubyte*)&renewalTime,
                        ODrenewaltime, renewalTime.sizeof);
                    optget(p.optdata, cast(ubyte*)&rebindingTime,
                        ODrebindingtime, rebindingTime.sizeof);

                    optget(p.optdata, cast(ubyte*)&lease, ODlease, lease.sizeof);
                    renewalTime = renewalTime.swapEndian;
                    rebindingTime = rebindingTime.swapEndian;
                    lease = lease.swapEndian;
                    ip = new dsin_addr(p.yiaddr, 0);
                    gateway = new dsin_addr(_sav.router, 0);
                    mask = new dsin_addr(_sav.mask, 0);

                    writeln("ip: ", p.yiaddr);
                    writeln("subnet mask: ", _sav.mask);

                    writeln("renewal: ", renewalTime);
                    writeln("rebinding: ", rebindingTime);
                    writeln("lease: ", lease);
                    status = true;
                    send(recvThread, false);
                    d.status = status;
                    d.ip = ip;
                    d.gateway = gateway;
                    d.mask = mask;

                    run = false;
                }

                if (type == DHCPnak)
                {
                    writeln("NAK");
                    run = false;
                }

                if (type == Timeout0)
                {
                    writeln("timeout!");
                }
            });
        }

        return d;

    }

    this(string _bindiface = "wlan0", string _iface = "veth0", string hostname = "")
    {
        ifreq _ifreq;
        sock = new Socket(AddressFamily.INET, SocketType.DGRAM, ProtocolType.UDP);
        bindiface = _bindiface;
        iface = _iface;
        sock.setOption(SocketOptionLevel.SOCKET, SocketOption.BROADCAST, 1);
        {
            ifreq _ifreq2;
            auto _cstr = toStringz(bindiface);
            strncpy(cast(char*) _ifreq2.ifr_name, _cstr, IFNAMSIZ);
            ioctl(sock.handle, SIOCGIFINDEX, &_ifreq2);

            if (setsockopt(sock.handle, SocketOptionLevel.SOCKET, 25,
                    &_ifreq2, _ifreq2.sizeof) == -1)
            {
                writefln("error: %s", fromStringz(strerror(errno)));
                assert(0);
            }

            sock.bind(new InternetAddress("255.255.255.255", 68));
        }

        sock.blocking(false);

        auto _cstr = toStringz(iface);
        strncpy(cast(char*) _ifreq.ifr_name, _cstr, IFNAMSIZ);
        ioctl(sock.handle, SIOCGIFHWADDR, &_ifreq);
        char[] hwaddr = cast(char[]) _ifreq.ifr_hwaddr.sa_data.dup;

        string mac = "";
        for (int i = 0; i < 6; i++)
        {
            _config.hwaddr[i] = hwaddr[i];
            _config.cid[i] = hwaddr[i];
            mac ~= format!"%x"(hwaddr[i]);
            if (i != 5)
            {
                mac ~= ":";
            }
        }

        if (hostname == "")
        {
            _config.hostname = sock.hostName;
        }

        import std.random;

        for (int i = 0; i < 4; i++)
        {
            _config.xid[i] = uniform!ubyte;
        }

        recvThread = spawn(&recvLoop, sock.handle, thisTid);
    }
}

dsin_addr getInterfaceIP(string iface)
{
    ifreq _ifreq;
    Socket sock = new Socket(AddressFamily.INET, SocketType.DGRAM, ProtocolType.IP);
    _ifreq.ifr_addr.sa_family = AddressFamily.INET;

    auto _cstr = toStringz(iface);
    strncpy(cast(char*) _ifreq.ifr_name, _cstr, IFNAMSIZ);
    ioctl(sock.handle, SIOCGIFADDR, &_ifreq);
    sock.close();

    ubyte[4] data = cast(ubyte[])(_ifreq.ifr_addr.sa_data[2 .. 6]);

    dsin_addr ret = new dsin_addr(data, 0);

    return ret;
}

/* ip, mask, gateway */
void setInterfaceIP(string iface, dsin_addr[3] _ip)
{
    ifreq _ifreq;
    rtentry rtreq;

    int fd;

    auto _cstr = toStringz(iface);
    strncpy(cast(char*) _ifreq.ifr_name, _cstr, IFNAMSIZ);

    writefln("interface: %s", iface);

    _ifreq.ifr_addr = _ip[0].toCAddr();

    Socket sock = new Socket(AddressFamily.INET, SocketType.DGRAM, ProtocolType.IP);
    writefln("error? %d", ioctl(sock.handle, SIOCSIFADDR, &_ifreq));
    writefln("errno: %s", fromStringz(strerror(errno)));

    _ifreq.ifr_netmask = _ip[1].toCAddr();
    writefln("error? %d", ioctl(sock.handle, SIOCSIFNETMASK, &_ifreq));
    _ifreq.ifr_flags = IFF_UP | IFF_RUNNING | IFF_BROADCAST | IFF_MULTICAST;
    writefln("error? %d", ioctl(sock.handle, SIOCSIFFLAGS, &_ifreq));

    /* gateway */

    rtreq.rt_flags = (RTF_UP | RTF_GATEWAY);
    rtreq.rt_gateway = _ip[2].toCAddr();
    rtreq.rt_genmask = new dsin_addr([0, 0, 0, 0], 0).toCAddr();
    rtreq.rt_dst = new dsin_addr([0, 0, 0, 0], 0).toCAddr();
    if (ioctl(sock.handle, SIOCADDRT, &rtreq) == -1)
    {
        writefln("error: %s", fromStringz(strerror(errno)));
    }

    sock.close();
}

void main(string[] args)
{
    import std.getopt;

    string bindIface = "wlan0";
    string iface = "wlan0";
    string hostname = "";

    auto helpInformation = getopt(args, "hostname", &hostname, "bind|b",
            &bindIface, "interface|i", &iface, "level|v", &level);

    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.", helpInformation.options);
        return;
    }

    dhcpclient cl = new dhcpclient(bindIface, iface, hostname);
    auto i = cl.dhcpRequest();
    if (i.status)
    {
        writeln("success");
        dsin_addr _iface = getInterfaceIP(iface);
        writeln("iface internal ip: ", _iface);
        writeln("iface external ip: ", i.ip);
    }
}
