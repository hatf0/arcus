module valkyrie.instance.firecracker.firecrackerdrive;
import std.stdio;
import firecracker_d.core.client;
import bap.core.resource_manager;

mixin MultiInstanceSingleton!("FirecrackerDrive");

final shared class FirecrackerDrive : OneConnectionResource {
	private {
		file_entry[] files = [
			{
			writable:
				false, name : "size", file_type
					: file_entry.file_types.raw, type : file_entry.types.typeInt64
			},
			{
			writable:
				false, name : "is_root_device", file_type
					: file_entry.file_types.raw, type : file_entry.types.typeBool
			},
			{
			writable:
				false, name : "is_read_only", file_type
					: file_entry.file_types.raw, type : file_entry.types.typeBool
			},
			{
			writable:
				false, name : "disk_template", file_type
					: file_entry.file_types.raw, type : file_entry.types.typeString
			}
		];
	}

	override file_entry[] getFiles() {
		return cast(file_entry[]) files;
	}

	override bool exportable() {
		return true;
	}

	override string getClass() {
		return "FirecrackerDrive";
	}

	override string getStatus() {
		if (attached) {
			return "ATTACHED";
		}

		return "FREE";
	}

	override bool connect(ResourceIdentifier id) {
		return true;
	}

	override bool disconnect(ResourceIdentifier id) {
		return true;
	}

	override bool canDisconnect(ResourceIdentifier id) {
		return false;
	}

	this(string data) {
		import bap.core.utils;

		self = idSelf(data);
		storage = cast(shared(ResourceStorage)) new ResourceStorage(cast(file_entry[]) files,
				idSelf(data));
	}

}
