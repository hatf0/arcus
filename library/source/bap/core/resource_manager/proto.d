module bap.core.resource_manager.proto;
import dproto.dproto;
import bap.core.resource_manager.filesystem;

mixin ProtocolBufferFromString!"
	message FilesystemResource {
		string path = 1;
		bytes data = 2;
		bool writable = 3;
		int32 type = 4;
	}

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
