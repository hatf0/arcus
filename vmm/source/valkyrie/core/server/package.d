module valkyrie.core.server;
import core.thread, core.time;
import bap.core.resource_manager;

class ValkryieServer {
private:
	string dataPath; //typically /srv/valkyrie
	string configPath; //typically /etc/valkyrie

	__gshared bool run = true;
	Thread listenerThread;


}
