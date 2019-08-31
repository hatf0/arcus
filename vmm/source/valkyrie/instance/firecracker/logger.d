module valkyrie.instance.firecracker.logger;
import bap.core.resource_manager;
/*

final shared class FirecrackerVmLoggerSingleton : ResourceSingleton {
	override Resource instantiate(string uuid) {
		shared(FirecrackerVmLogger) logger = new shared(FirecrackerVmLogger)();

		return cast(Resource) logger;

	}

	this() {
		mtx = new shared(Mutex)();
	}
}

static shared(FirecrackerVmLoggerSingleton) g_FirecrackerVmLoggerSingleton;

import firecracker_d.models.logger;

//for this resource, it doesn't matter for it to really deploy as it does for it to connect

//as 

final shared class FirecrackerVmLogger : Resource {
private:
	bool deployed;
	string __socketPath;
	string __metricsPath;
	string __logPath;
	bool showLevel;
	bool showLogOrigin;
	string[] options = ["LogDirtyPages"];
	LoggerLevel level;
public:

	override bool exportable() {
		return true;
	}

	override string getClass() {
		return "FirecrackerVmLogger";
	}

	override string getStatus() {
		if (deployed) {
			return "OK";
		}

		return "NOTOK";
	}

	override bool destroy() {
		//should be called on shutdown
		deployed = false;
		return true;
	}

	override bool deploy() {
		return true;
	}

	override bool connect(ResourceIdentifier id) {
		import firecracker_d.core.client;

		shared(Resource) _vm = g_ResourceManager.getResource(id);
		_vm.useResource();
		{
			if (_vm.getClass() != "FirecrackerVm") {
				return false;
			}

			import valkyrie.instance.firecracker.firecrackervm;

			shared(FirecrackerVm) vm = cast(shared(FirecrackerVm)) _vm;

			Logger log;
			log.logFifo = __logPath;
			log.metricsFifo = __metricsPath;
			log.showLevel = showLevel;
			log.showLogOrigin = showLogOrigin;
			log.options = cast(string[]) options.dup;

			import std.file : exists;

			if (!exists(__socketPath)) {
				return false;
			}

			__socketPath = vm.socketPath;

			FirecrackerAPIClient push = new FirecrackerAPIClient(vm.socketPath);
			log.put(push);
		}
		_vm.releaseResource();
		deployed = true;
		return true;

	}

	override bool disconnect(ResourceIdentifier id) {
		assert(canDisconnect(id), "called while canDisconnect == false");

		return false;

	}

	override bool canDisconnect(ResourceIdentifier id) {
		return false;
	}

	this() {
		mtx = new shared(Mutex)();
	}
}
*/
