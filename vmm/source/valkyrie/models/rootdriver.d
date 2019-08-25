module valkyrie.models.rootdriver;
import valkyrie.models.nic;
import bap.core.utils;

mixin ProtocolBufferFromString!"
	enum Events {
		ALLOCATE_NIC = 0;
		ALLOCATE_IP = 1;
		ALLOCATE_NIC = 2;
		ADD_NIC_TO_BR = 3;
		UPDATE_NIC_NSG = 4;
		UPDATE_NIC = 5;
	}

	message UpdateNICNSG {
		string iface = 1;
		SecurityPolicy secpol = 2;
	}

	message AllocateMAC {

	}

	message AllocateIP {

	}

	message AllocateNIC {

	}

	message AddNICToBridge {
		string iface = 1;
		string bridge = 2;
	}

	message UpdateNIC {
		string iface = 1;
		string ip = 2;
		string mac = 3;
	}

	message RootDriverEvt {
		Events evt = 1;
		optional AllocateMAC allocateMAC = 2;
		optional AllocateIP allocateIP = 3;
		optional AllocateNIC allocateNIC = 4;
		optional AddNICToBridge addNICToBridge = 5;
		optional UpdateNICNSG updateNICNSG = 6;
		optional UpdateNIC updateNIC = 7;
	}


";
