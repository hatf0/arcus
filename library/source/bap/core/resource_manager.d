module bap.core.resource_manager;
import std.string;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.datetime;
public import std.variant : Variant;
public import core.sync.mutex;
public import dproto.dproto;

import core.stdc.errno;
static __gshared ResourceManager g_ResourceManager;
static int activeMutexes = 0;


//TODO: replace with Mutex with ReadWriteMutex?

// Here be dragons..
mixin template ResourceInjector(string resourceName, string path = "scylla.core") {
	import std.string;
	mixin("import " ~ path ~ "." ~ resourceName.toLower() ~ "; bool instantiated" ~ resourceName ~ " = () {g_" ~ resourceName ~ "Singleton = new shared(" ~ resourceName ~ "Singleton); g_ResourceManager.registerClass(\"" ~ resourceName ~ "\", cast(Resource delegate(string))&g_" ~ resourceName ~ "Singleton.instantiate); return true;}();");

}

mixin ProtocolBufferFromString!"
	message ResourceIdentifier {
		ZoneIdentifier zone = 1;
		string uuid = 2;
	}

	message ZoneIdentifier {
		string zoneId = 1;
	}

	message Zone {
		string location = 1;
		string name = 2;
	}

	message FilesystemResource {
		string path = 1;
		bytes data = 2;
		bool writable = 3;
		int32 type = 4;
	}


	message MinimalResource {
		string creation_time = 1;
		ResourceIdentifier id = 2;
		repeated FilesystemResource resources = 3;
		string resourceClass = 4;
		bool deployed = 5;
		bool single_connection = 6;
		repeated ResourceIdentifier connections = 7;
	}

";

static __gshared string filePath;
static __gshared string backupPath;
void runMount(Fuse obj, Operations op, string path) {
		obj.mount(op, path, []);
}

import dfuse.fuse;

//TODO: can we like.. not deal with const(char)[]s? i don't like using toStringz


/* 
   In your resource, specify an array of these for persistent storage of variables (i.e size, etc)
*/

struct file_entry {
	enum file_types {
		json, //appends .json to the end
		xml, //appends .xml to the end
		plaintext, //appends .txt to the end
		log, //appends .log to the end
		raw //raw data
	};

	enum types {
		typeBool,
		typeString,
		typeFloat,
		typeInt,
		typeInt64,
		typeRaw 
	};

	bool writable;
	string name;
	ubyte[] buf;
	file_types file_type;
	types type;
};

struct ResourceFile {
	bool writable;
	ubyte[] buf;
	file_entry.types type;
}

import std.algorithm.searching : canFind;

import std.stdio : writefln;

/*
   This simple FUSE driver ensures that any config files accessed
   are writable, as specified in your file_entry[] array, which was
   passed to the constructor. It is optional to use this class,
   as some resources MAY not need it.
*/
	
class ResourceStorage : Operations {
	private {
		ResourceFile[string] files;
		file_entry[] configurations;
	}
	//should probably store the configuration/log files here?

	@property
	shared Variant opIndex(string path) 
	in {
		assert(path in files, "Path did not exist in the array");
	}
	do {
		import std.bitmanip : read;
		Variant ret = 0;

		ubyte[] _buf = cast(ubyte[])(files[path].buf).dup;

		if(_buf.length == 0) { 
			return ret;
		}

		switch(files[path].type) {
			case file_entry.types.typeRaw:
				ret = files[path].buf;
				goto default;
			case file_entry.types.typeBool:
				ret = _buf.read!bool();
				goto default;
			case file_entry.types.typeFloat:
				ret = _buf.read!float(); 
				goto default;
			case file_entry.types.typeInt: 
				ret = _buf.read!int();
				goto default;
			case file_entry.types.typeInt64:
				ret = _buf.read!long();
				goto default;
			case file_entry.types.typeString:
				ret = cast(string)_buf;
				goto default;
			default:
				return ret;
		}
		
		
	}

	import std.stdio : writeln;
	@property
	shared Variant opIndexAssign(Variant dat, string path) 
	in {
		assert(path in files, "Path did not exist in the array");
		file_entry.types expectedType;
		if(dat.type == typeid(ubyte[])) {
			expectedType = file_entry.types.typeRaw;
		}
		else if(dat.type == typeid(float)) {
			expectedType = file_entry.types.typeFloat;
		}
		else if(dat.type == typeid(int)) {
			expectedType = file_entry.types.typeInt;
		}
		else if(dat.type == typeid(bool)) {
			expectedType = file_entry.types.typeBool;
		}
		else if(dat.type == typeid(long)) {
			expectedType = file_entry.types.typeInt64;
		}
		else if(dat.type == typeid(string)) {
			expectedType = file_entry.types.typeString;
		}

		writeln(files[path].type);
		writeln(expectedType);

		assert(files[path].type == expectedType, "Requested write did not match the file type.");
	}
	do
	{
		import std.bitmanip : write;
		ubyte[] _buf;
		try {
		if(dat.type == typeid(ubyte[])) {
			auto data = dat.get!(ubyte[]);
			_buf.length = data.length;
			files[path].buf = cast(shared(ubyte[]))data.dup; 
			return dat;
		}
		else if(dat.type == typeid(float)) {
			auto data = dat.get!(float);
			_buf.length = float.sizeof;
			_buf.write!float(data, 0);
		}
		else if(dat.type == typeid(bool)) {
			auto data = dat.get!(bool);
			_buf.length = bool.sizeof;
			_buf.write!bool(data, 0);
		}
		else if(dat.type == typeid(long)) {
			auto data = dat.get!(long);
			_buf.length = long.sizeof;
			_buf.write!long(data, 0);
		}
		else if(dat.type == typeid(int)) {
			auto data = dat.get!(int);
			_buf.length = int.sizeof;
			_buf.write!int(data, 0);
		}
		else if(dat.type == typeid(string)) {
			auto data = dat.get!(string);
			_buf.length = data.length;
			files[path].buf = cast(shared(ubyte[]))data.dup;
			return dat;
		}
		} catch(Exception e) {
			writeln("exception");
			writeln(e.msg);
		}

		files[path].buf = cast(shared(ubyte[]))_buf.dup;
		return dat;
	}
		

	override void getattr(const(char)[] path, ref stat_t s) {
		import std.conv;
		import std.string;
		if(path == "/") {
			s.st_mode = S_IFDIR | octal!755;
			s.st_size = 0;
			return;
		}

		/* 
		TODO: rework into something more efficient (B-tree?) 
		for now, will work due to the fact that this SHOULDN'T
		have too many files
		*/

		foreach(c; files.keys) {
			if(path.idup == "/" ~ c) {
				s.st_mode = S_IFREG | octal!644;
				ResourceFile file = files[c];
				s.st_size = file.buf.length + 1;
				return;
			}
		}
		throw new FuseException(ENOENT);
	}

	override string[] readdir(const(char)[] path) {
		string[] ret = [".", ".."];
		if(path == "/") {
			foreach(c; files.keys) {
				ret ~= c;
			}
		}
		return ret;
	}

	override bool access(const(char)[] _path, int mode) {
		return true;
	}

	override void truncate(const(char)[] _path, ulong length) {
		string path = _path[1..$].idup;
		if(files.keys.canFind(path)) {
			ResourceFile fi = files[path];
			if(fi.writable) {
				debug writefln("resize from %d to %d", fi.buf.length, length);
				files[path].buf.length = length;
			}
			else {
				throw new FuseException(EACCES);
			}
		}
	}

	override int write(const(char)[] _path, const(ubyte[]) buf, ulong offset) {
		debug writefln("path: %s", _path.idup);
		string path = _path[1..$].idup;
		if(files.keys.canFind(path)) {
			ResourceFile file = files[path];
			if(offset > file.buf.length) {
				debug writefln("requested write to %d while length was %d", offset, file.buf.length);
				file.buf.length += (buf.length) - 1;
			}

			if(!file.writable) {
				throw new FuseException(EACCES);
			}
			ubyte[] range;

			if(offset != 0) {
				range = file.buf[offset - 1..$];
			}
			else {
				range = file.buf[offset..$];
			}

			debug writefln("size of range: %d", range.length);

			if(range.length < buf.length) {
				debug writefln("size is way smaller! %d < %d", range.length, buf.length);

				debug writefln("resizing to %d", (file.buf.length + (buf.length - range.length)));
				file.buf.length += (buf.length - range.length);
			}

			if(offset != 0) {

				file.buf[offset - 1..$] = buf;
			} else {
				file.buf[offset..$] = buf;
			}

			files[path].buf = file.buf;
			
			debug writefln("size of original array: %d, size of file array: %d", buf.length, file.buf.length);
		}
		return cast(int)buf.length;
	}


	override ulong read(const(char)[] _path, ubyte[] buf, ulong offset) {

		debug writefln("path: %s", _path.idup);
		string path = _path[1..$].idup; //ignore the first slash
		if(files.keys.canFind(path.idup)) {
			ResourceFile file = files[path.idup];
			if(offset > file.buf.length) {
				throw new FuseException(EIO);
			}

			import std.algorithm.mutation : copy;
			ubyte[] copy_buf = file.buf[offset..$];
			if(copy_buf.length > 4096) {
				copy_buf = copy_buf[0..4096]; //resize
			}

			//if(copy_buf.length != 4096) {
			//	copy_buf ~= '\n';
			//}

			copy_buf.copy(buf);
//`			buf = [0xA0, 0x77, 0xA0, 0x77];

			//buf = file.buf[offset..$].dup;

			debug writefln("read %d bytes", copy_buf.length);

			return copy_buf.length;
		}
		throw new FuseException(EOPNOTSUPP);
	}

	void importBak(FilesystemResource[] data) {
		foreach(f; data) {
			ResourceFile _f = ResourceFile();
			_f.buf = f.data.dup;
			_f.type = cast(file_entry.types)f.type;
			_f.writable = f.writable;
			files[f.path] = _f; 
		}
	}


	FilesystemResource[] exportAll() {
		FilesystemResource[] res;
		foreach(k; files.keys) {
			FilesystemResource _f = FilesystemResource();
			ResourceFile file = files[k];
			_f.data = file.buf.dup;
			_f.writable = file.writable;
			_f.path = k;
			_f.type = file.type;
			res ~= _f;
		}
		return res;
	}

	ubyte[] exportData(string path) {
		FilesystemResource f = FilesystemResource();
		if(files.keys.canFind(path)) {
			ResourceFile file = files[path];
			f.data = file.buf.dup;
			f.writable = file.writable;
			f.type = file.type;
			f.path = path;
		}

		return f.serialize();
	}



	this(file_entry[] entries, ResourceIdentifier id) {
		configurations = entries;
		ResourceFile uuid_file = ResourceFile();
		import std.stdio : writefln;

		debug writefln("%s", id.uuid);
		uuid_file.buf = cast(ubyte[])id.uuid.dup ~ '\n';
		uuid_file.writable = false;
		uuid_file.type = file_entry.types.typeString;
		files["uuid"] = uuid_file;

		ResourceFile zone_file = ResourceFile();
		zone_file.buf = cast(ubyte[])id.zone.zoneId ~ '\n';
		zone_file.writable = false;
		zone_file.type = file_entry.types.typeString;
		files["zone"] = zone_file;

		foreach(c; configurations) {
			string path = c.name;
			switch(c.file_type) {
				case file_entry.file_types.json:
					path ~= ".json";
					break;
				case file_entry.file_types.xml:
					path ~= ".xml";
					break;
				case file_entry.file_types.log:
					path ~= ".log";
					break;
				case file_entry.file_types.raw:
					break;
				default:
					path ~= ".txt";
			}

			ResourceFile fi = ResourceFile();

			fi.buf = c.buf.dup;
			fi.type = c.type;

			fi.writable = c.writable;
			
			assert(files.keys.canFind(path) is false, "files[path] should be null!");
			files[path] = fi; 
		}

	}
}

/*
	NOTE: any public/private vars will NOT be stored
	and repopulated, except for those which are default.
	This is by design, and to force all programmers who
	want persistent storage to use the ResourceStorage
	class.
*/

shared class Resource {
	protected {
		bool deployed = false;
		Mutex mtx;
		ResourceIdentifier self;

		DateTime creation_date; 
	}

	/* 
	   Persistent storage for variables
	   Persists even across restarts of the program
	   Store nothing sensitive in this
	 */
	ResourceStorage storage; 

	file_entry[] getFiles() {
		return null;
	}

	abstract string getClass(); 
	abstract string getStatus();
	abstract bool exportable();

	@property
	Variant opDispatch(string target)() const {

		Variant ret = 0;

		if(storage != null) {
			string var = target;
			foreach(file; getFiles()) {
				if(file.name == var) {
					Variant storedFile = storage[var];
					return storedFile;
				}
			}
		}
		else {
			assert(0, "opDispatch called on an object with no storage..");
		}

		return ret;
	}


	ubyte[] exportResource() {
		// The MinimalResource struct
		// ensures that we can keep data
		// even after we have restarted the
		// application. It saves only the 
		// bare minimum, which includes
		// filesystem contents, connections,
		// it's class, it's creation time
		// and nothing else. 
		// It is assumed that the programmer
		// will use the ResourceStorage
		// to store configurations and have
		// it persistent.
		if(!exportable) {
			return null;
		}
		MinimalResource res = MinimalResource();
		DateTime _creation = creation_date;
		res.creation_time = _creation.toISOExtString();
		res.id = self;
		res.deployed = deployed;
		res.connections = g_ResourceManager.getConnections(self);  
		if(storage !is null) {
			ResourceStorage _storage = cast(ResourceStorage)storage;
			res.resources = _storage.exportAll();
		}

		res.resourceClass = getClass();

		return res.serialize();
	}
	bool destroy() {
		import std.process, std.file;

		import std.stdio : writefln;

		if(storage is null) {
			return true;
		}

		string path = filePath ~ "/" ~ self.uuid;

		debug writefln("path: %s", path);

		import core.thread, core.time;

		auto umount_tid = spawnProcess(["/usr/bin/umount", "-lf", path]);
		auto umount = tryWait(umount_tid); 

		debug writefln("code: %d", umount.status);
		if(umount.status != 0) {
			string[] mounts = readText("/proc/mounts").split('\n');
			bool found = false;
			foreach(mount; mounts) {
				import std.algorithm.searching;
				if(mount.canFind(path)) {
					found = true;
				}
			}
				
			assert(!found, "failed to unmount a path which is mounted");
		}
		debug writefln("unmounted %s successfully", path);

		debug writefln("trying to remove %s", path);

		/*
		   THIS WILL PROBABLY HANG IF ANYTHING IS IN USE
		   BUT SADLY I CAN'T ADD THREAD.SLEEP BECAUSE NANOSLEEP
		   FUCKS UP CONTROL FLOW SOMEHOW??
		*/

		/* 
		   WTF?
		*/

		while(exists(path) && isDir(path)) {
			try {
				rmdir(path);
			} catch(Exception e) {
			}
		}

		return true;
	}

	bool deploy() {
		/* DANGEROUS */
		if(deployed) {
			return false;
		}

		ResourceStorage st = cast(ResourceStorage)storage;
		if(!(st is null)) {
			ResourceIdentifier id = cast(ResourceIdentifier)self;

			g_ResourceManager.requestMount(st, self);
			deployed = true;
		}
		return true;
	}
		
	abstract bool connect(ResourceIdentifier id) {
		return true;
	}
	abstract bool disconnect(ResourceIdentifier id);
	abstract bool canDisconnect(ResourceIdentifier id);

	void useResource() shared @safe nothrow @nogc 
	{
		import core.thread;
		import std.datetime;
		while(mtx.tryLock_nothrow() == false) {
			() @trusted {Thread.sleep(1.msecs);}();
		}

		activeMutexes++;

	}

	void releaseResource() shared @safe nothrow @nogc
	{
		assert(activeMutexes != 0, "releaseResource called when there are no active mutexes!");

		activeMutexes--;
		mtx.unlock_nothrow();
	}
}

/*
   Use the ResourceSingleton base as your main
   constructor for any resource.

   Obtaining the mutex is unnecessary- as this is only
   likely to be accessed by the ResourceManager thread.
*/

shared class ResourceSingleton {
	Mutex mtx;
	abstract Resource instantiate(string data);
	void useResource() shared @safe nothrow @nogc 
	{
		mtx.lock_nothrow();
	}

	void releaseResource() shared @safe nothrow @nogc
	{
		mtx.unlock_nothrow();
	}

}

shared class OneConnectionResource : Resource { //for example, network interfaces
	bool attached = false;
	ResourceIdentifier owner;
}


/*
   This ResourceManager handles multi-threaded sharing of resources,
   as well as dynamic instantiation at runtime. Classes are imported with the ResourceInjector mixin,
   then instantiated with it's constructor from the singleton instance
   at runtime. This helps make the code more generic, as I don't
   have to write several files dedicated towards specific modules,
   and I can just inject them at runtime.

NOTE: All resources require a singleton which creates a shared
instance of the resource! This is a requirement of the dynamic
instantiation system!
*/

class ResourceManager {
	private {
		Fuse[] resourceFS;
		shared(Resource)[string] _resources;
		ResourceIdentifier[][string] _connections;

		Resource delegate(string)[string] _instanceTable;
		string askForUUID() {
			import std.uuid;
			while(true) {
				auto uuid = randomUUID();
				if(!(uuid.toString() in _resources)) {
					return uuid.toString();
				}
			}
		}	
	}

	string[] getAllResourceClasses() {
		return _instanceTable.keys.dup;
	}

	string[] getAllResources() {
		return _resources.keys.dup;
	}

	bool isValidClass(string className) {
		if(className in _instanceTable) {
			return true;
		}
		return false;
	}

	void registerClass(string _className, Resource delegate(string) dlg) {
		assert(!(_className in _instanceTable), "Cannot override delegate for class..");

		assert(dlg != null, "dlg was null!");

		_instanceTable[_className] = cast(Resource delegate(string))dlg;
	}

	ResourceIdentifier instantiateFromBackup(ubyte[] data) {
		MinimalResource res = MinimalResource(data);
		assert(res.resourceClass in _instanceTable, "Non-existant class loaded");
		
		Resource r = _instanceTable[res.resourceClass](res.id.uuid);
		assert(!(r is null), "Resource was null when attempting to load from a backup.");

		r.creation_date = cast(shared(DateTime))DateTime.fromISOExtString(res.creation_time);
		_connections[res.id.uuid] = res.connections;

		if(r.storage !is null) {
			ResourceStorage _storage = cast(ResourceStorage)r.storage;
			_storage.importBak(res.resources);
		}

		if(res.deployed) {
			shared(Resource) _s = cast(shared(Resource))r;
			assert(_s.deploy(), "Deploy failed..");
		}

		_resources[res.id.uuid] = cast(shared(Resource))r;

		return res.id;
	}

	ResourceIdentifier instantiateResource(string _class) {
		assert(_class in _instanceTable, "Class must exist..");

		string objectUUID = askForUUID();
		Resource r = _instanceTable[_class](objectUUID);

		assert(!(r is null), "Resource was null during instantiation");

		import bap.core.utils;

		r.creation_date = cast(shared(DateTime))Clock.currTime();

		_resources[objectUUID] = cast(shared Resource)r;
		

		return id("example", objectUUID);
	}

	string resourceStatus(ResourceIdentifier id) {
		if(id.uuid in _resources) {
			shared Resource r = _resources[id.uuid];
			r.useResource();
			string status = r.getStatus().idup;
			r.releaseResource();

			return status;
		}
		else {
			return "NO_EXIST";
		}
	}

	bool destroyResource(ResourceIdentifier id) {
		if(id.uuid in _resources) {
			if(id.uuid in _connections) {
			}
			shared Resource r = _resources[id.uuid];
			r.useResource();
			bool status = r.destroy();
			r.releaseResource();

			_resources.remove(id.uuid);
			return status;
		}
		return false;
	}

	shared(Resource) getResource(ResourceIdentifier id) {
		if(id.uuid in _resources) {
			return _resources[id.uuid];
		}
		return null;
	}

	bool associateResource(ResourceIdentifier resource, ResourceIdentifier target) {
		if(resource.uuid in _resources) {
			if(target.uuid in _resources) {
				if(resource.uuid in _connections) {
					_connections[resource.uuid] ~= target;
				}
				else {
					_connections[resource.uuid] = [target];
				}

				if(target.uuid in _connections) {
					_connections[target.uuid] ~= resource;
				}
				else {
					_connections[target.uuid] = [resource];
				}

				return true;
			}
		}
		return false;
	}

	bool disassociateResource(ResourceIdentifier resource, ResourceIdentifier target) {
		if(resource.uuid in _resources) {
			if(target.uuid in _resources) {
				if(resource.uuid in _connections) {
					if(target.uuid in _connections) {
						if(_connections[resource.uuid].canFind(target)) {
							if(_connections[target.uuid].canFind(resource)) {
								foreach(i, con; _connections[target.uuid]) {
									if(con.uuid == resource.uuid) {
										_connections[target.uuid].remove(i);
									}
								}

								foreach(i, con; _connections[resource.uuid]) {
									if(con.uuid == target.uuid) {
										_connections[resource.uuid].remove(i);
									}
								}
							}
						}

					}
					else {
						return false;
					}
				}
				else {
					return false;
				}

			}
		}
		return false;
	}


	void cleanup() {
		import std.stdio;
		debug writefln("called to cleanup!");
		// PROGRAM IS ABOUT TO SHUTDOWN ANYWAYS!
		foreach(d, k; _resources) {
			import std.file : write;
			if(!(k is null)) {
				if(k.exportable()) {
					debug writefln("writing out %s", k.self.uuid);
					write(backupPath ~ "/" ~ k.self.uuid ~ ".bak", k.exportResource());
				}
				debug writefln("destroying resource %s", k.self.uuid);
				assert(k.destroy(), "failed to destroy object");
			}
		}

		writefln("done!");
	}


	bool requestMount(Operations op, ResourceIdentifier id) {
		import std.file;
		string path = filePath ~ "/" ~ id.uuid ~ "/";
		import std.stdio : writefln;
		debug writefln("requested mount to %s", path);
		if(!exists(path)) {
			try {
				mkdir(path);
			} catch(Exception e) {
			}
		}
		import std.parallelism;


		Fuse obj = new Fuse("ResourceStorage", true, true);
		resourceFS ~= obj;
		auto fsRun = task!runMount(obj, op, path);
		fsRun.executeInNewThread();

		return true;
	}

	ResourceIdentifier[] getConnections(ResourceIdentifier id) {
		ResourceIdentifier[] connections;
		if(id.uuid in _connections) {
			ResourceIdentifier[] connMap = _connections[id.uuid];
			foreach(connection; connMap) {
				connections ~= connection;
			}
		}
		return connections;

	}

	this() {
	}

}


	
