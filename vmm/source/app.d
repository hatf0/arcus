import vibe.vibe;
import bap.core.resource_manager;

void main() {
	import core.sys.posix.unistd;

	uid_t ruid = getuid();

	assert(ruid == 0, "valkyrie must be run as root");
	import std.file;

	/* Ensure that a 'kvm' group actually exists */
	auto n = slurp!(string, string, int, string)("/etc/group", "%s:%s:%d:%s");
	bool kvmGroup = false;
	foreach (k; n) {
		if (k[0] == "kvm") {
			kvmGroup = true;
			break;
		}
	}
	assert(kvmGroup, "expected kvm group to exist");
	g_ResourceManager = new ResourceManager();
	mixin ResourceInjector!("LogEngine", "bap.core.logger");

}
