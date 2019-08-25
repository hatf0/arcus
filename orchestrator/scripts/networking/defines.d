module defines;

public import core.stdc.time;
public import std.bitmanip;
public import core.sys.posix.sys.ioctl;
public import core.stdc.errno, core.stdc.string;
public import std.socket;

struct bootp {
	ubyte op;
	ubyte htype;
	ubyte hlen;
	ubyte hops;
	ubyte[4] xid;
	ubyte[2] secs;
	ubyte[2] flags;
	ubyte[4] ciaddr;
	ubyte[4] yiaddr;
	ubyte[4] siaddr;
	ubyte[4] giaddr;
	ubyte[16] chaddr;
	ubyte[64] sname;
	ubyte[128] file;
	ubyte[4] magic;
	ubyte[312 - 4] optdata;
	/* optdata is laid out as such:
	   [code] [len] [data with a size of len] ...
	   repeat until OPTend is hit
	*/
}

void optget(ubyte[] p, ubyte* data, int opt, int n) {
	int i = 0;
	while (i < p.length) {
		int code = p[i++];
		if (code == OBpad)
			continue;

		if (code == OBend || i == p.length)
			break;

		int len = p[i++];

		if (len > p.length - i)
			break;

		if (code == opt) {
			for (int k = 0; k < len; k++) {
				data[k] = p[i + k];
			}
			break;
		}

		i += len;
	}
}

ubyte[] hnoptput(ref ubyte[] p, int opt, uint data, size_t len) {
	int index = 0;
	p[index++] = cast(ubyte) opt;
	p[index++] = cast(ubyte) len;
	p.write!uint(data.swapEndian, index++);

	return p[index .. $ - 1];
}

ubyte[] optput(ref ubyte[] p, int opt, ubyte[] data) {
	int index = 0;
	p[index++] = cast(ubyte) opt;
	p[index++] = cast(ubyte)(data.length);
	assert(((index + (data.length)) - index) == data.length, "index violation");

	foreach (i, l; data) {
		p[index++] = l;
	}

	return p[index .. $ - 1];
}

void hnput(ubyte* dst, uint src, size_t n) {
	int i;
	for (i = 0; n--; i++) {
		dst[i] = (src >> (n * 8)) & 0xFF;
	}
}

class dsin_addr {
private:
	void setFields(ubyte[4] _ip) {
		ubyte[4] ip = _ip.dup;
		a = ip[0];
		b = ip[1];
		c = ip[2];
		d = ip[3];
	}

public:
	int port;

	union {
		uint value;
		mixin(bitfields!(uint, "a", 8, uint, "b", 8, uint, "c", 8, uint, "d", 8));
	}

	ubyte[4] toArray() {
		import std.algorithm;

		ubyte[] array;
		import std.typecons : Flag, Yes;

		[a, b, c, d].each!((uint n) { array ~= cast(ubyte) n; return Yes.each; });

		return array[0 .. 4];
	}

	sockaddr toCAddr() {
		sockaddr_in addr;

		addr.sin_family = AF_INET;
		addr.sin_port = htons(cast(uint16_t) port);
		addr.sin_addr.s_addr = value;

		return cast(sockaddr) addr;
	}

	override string toString() {
		import std.format;

		return format!"%d.%d.%d.%d"(a, b, c, d);
	}

	void opAssign(ubyte[4] ip) {
		setFields(ip);
	}

	this(ubyte[4] ip, int port) {
		setFields(ip);
		port = port;
	}

}

enum {
	DHCPdiscover = 1,
	DHCPoffer,
	DHCPrequest,
	DHCPdecline,
	DHCPack,
	DHCPnak,
	DHCPrelease,
	DHCPinform,
	Timeout0 = 200,
	Timeout1,
	Timeout2,

	/* bootp */
	Bootrequest = 1,
	Bootreply = 2,
	/* bootp flags */
	Fbroadcast = 1 << 15,

	/* OB/OD */
	OBpad = 0,
	OBmask = 1,
	OBrouter = 3,
	OBnameserver = 5,
	OBdnsserver = 6,
	OBhostname = 12,
	OBbaddr = 28,
	ODipaddr = 50,
	ODlease = 51,
	ODoverload = 52,
	ODtype = 53,
	ODserverid = 54,
	ODparams = 55,
	ODmessage = 56,
	ODmaxmsg = 57,
	ODrenewaltime = 58,
	ODrebindingtime = 59,
	ODvendorclass = 60,
	ODclientid = 61,
	ODtftpserver = 66,
	ODbootfile = 67,
	OBend = 255,
};

enum {
	Broadcast,
	Unicast
};

struct if_settings {
	uint type; /* Type of physical device or protocol */
	uint size; /* Size of the data allocated by the caller */
	union ifs_ifsu {
		/* {atm/eth/dsl}_settings anyone ? */
		void* raw_hdlc;
		void* cisco;
		void* fr;
		void* fr_pvc;
		void* fr_pvc_info;

		/* interface settings */
		void* sync;
		void* te1;
	};

	ifs_ifsu _ifs_ifsu;
};

struct ifreq {
	private union ifr_ifrn_ {
		byte[IFNAMSIZ] ifrn_name; /* if name, e.g. "en0" */
	}

	ifr_ifrn_ ifr_ifrn;

	private union ifr_ifru_ {
		sockaddr ifru_addr;
		sockaddr ifru_dstaddr;
		sockaddr ifru_broadaddr;
		sockaddr ifru_netmask;
		sockaddr ifru_hwaddr;
		short ifru_flags;
		int ifru_ivalue;
		int ifru_mtu;
		ifmap ifru_map;
		byte[IFNAMSIZ] ifru_slave; /* Just fits the size */
		byte[IFNAMSIZ] ifru_newname;
		byte* ifru_data;
		if_settings _ifsettings;
	}

	ifr_ifru_ ifr_ifru;

	// NOTE: alias will not work : alias ifr_ifrn.ifrn_name	    ifr_name;
	@property ref ifr_name() {
		return ifr_ifrn.ifrn_name;
	} /* interface name */

	@property ref ifr_addr() {
		return ifr_ifru.ifru_addr;
	}

	@property ref ifr_netmask() {
		return ifr_ifru.ifru_netmask;
	}

	@property ref ifr_flags() {
		return ifr_ifru.ifru_flags;
	}

	@property ref ifr_hwaddr() {
		return ifr_ifru.ifru_hwaddr;
	}
}

struct rtentry {
	ulong rt_pad1;
	sockaddr rt_dst; /* target address		*/
	sockaddr rt_gateway; /* gateway addr (RTF_GATEWAY)	*/
	sockaddr rt_genmask; /* target network mask (IP)	*/
	ushort rt_flags;
	short rt_pad2;
	ulong rt_pad3;
	void* rt_pad4;
	short rt_metric; /* +1 for binary compatibility!	*/
	byte* rt_dev; /* forcing the device at add	*/
	ulong rt_mtu; /* per route MTU/Window 	*/
	ulong rt_window; /* Window clamping 		*/
	ushort rt_irtt; /* Initial RTT			*/
};

struct ifmap {
	ulong mem_start;
	ulong mem_end;
	ushort base_addr;
	ubyte irq;
	ubyte dma;
	ubyte port;

}

enum IFNAMSIZ = 16;

enum {
	RTF_UP = 0x0001, /* route usable		  	*/
	RTF_GATEWAY = 0x0002, /* destination is a gateway	*/
	RTF_HOST = 0x0004, /* host entry (net otherwise)	*/
	RTF_REINSTATE = 0x0008, /* reinstate route after tmout	*/
	RTF_DYNAMIC = 0x0010, /* created dyn. (by redirect)	*/
	RTF_MODIFIED = 0x0020, /* modified dyn. (by redirect)	*/
	RTF_MTU = 0x0040, /* specific MTU for this route	*/
	RTF_WINDOW = 0x0080, /* per route window clamping	*/
	RTF_IRTT = 0x0100, /* Initial round trip time	*/
	RTF_REJECT = 0x0200 /* Reject route			*/
}
enum {
	IFF_UP = 0x1, /* Interface is up.  */

	IFF_BROADCAST = 0x2, /* Broadcast address valid.  */

	IFF_DEBUG = 0x4, /* Turn on debugging.  */

	IFF_LOOPBACK = 0x8, /* Is a loopback net.  */

	IFF_POINTOPOINT = 0x10, /* Interface is point-to-point link.  */

	IFF_NOTRAILERS = 0x20, /* Avoid use of trailers.  */

	IFF_RUNNING = 0x40, /* Resources allocated.  */

	IFF_NOARP = 0x80, /* No address resolution protocol.  */

	IFF_PROMISC = 0x100, /* Receive all packets.  */

	/* Not supported */
	IFF_ALLMULTI = 0x200, /* Receive all multicast packets.  */

	IFF_MASTER = 0x400, /* Master of a load balancer.  */

	IFF_SLAVE = 0x800, /* Slave of a load balancer.  */

	IFF_MULTICAST = 0x1000, /* Supports multicast.  */

	IFF_PORTSEL = 0x2000, /* Can set media type.  */

	IFF_AUTOMEDIA = 0x4000, /* Auto media select active.  */

	IFF_DYNAMIC = 0x8000 /* Dialup device with changing addresses.  */

};
