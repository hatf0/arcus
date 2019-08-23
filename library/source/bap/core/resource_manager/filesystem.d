module bap.core.resource_manager.filesystem;
import dfuse.fuse;
import std.variant;
import bap.core.resource_manager.proto;
import core.stdc.errno;
import std.stdio : writefln;
import std.algorithm.searching : canFind;

void runMount(Fuse obj, Operations op, string path) {
		obj.mount(op, path, []);
}

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

