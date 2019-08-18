module scylla.core.server.server;
import std.stdio;
import bap.core.node;
import bap.model;
import bap.core.redis;
import bap.core.db;
import scylla.models.config.scylla;
import scylla.core.root.rootdriver;
import vibe.web.auth;
import vibe.http.session;
import vibe.web.web : noRoute;
import scylla.core.server.kintsugi;
import scylla.core.utils;
import asdf;
import bap.core.resource_manager;

class ScyllaServer {
    private {
        ScyllaConfig serverConfig;
        RedisDatabaseDriver db;
        Kintsugi vmServer;
	RootDriver root;

        string configPath;
    };

    void loadConfig(string path = "./config.json") {
        import std.file, std.json, jsonizer;
        if(exists(path)) {
            string c = cast(string)read(path);
            JSONValue _c = parseJSON(c);
            serverConfig = fromJSON!ScyllaConfig(_c);
	    log(LogLevel.INFO, "loaded arcus config from " ~ path);
        }
        else {
            serverConfig = ScyllaConfig();
	    log(LogLevel.INFO, "creating new config");
	    saveConfig(configPath);
        }
    }

    void saveConfig(string path = "") {
        if(path == "") {
            path = configPath;
        }

        import std.file;
        try {
            write(path, serverConfig.stringify);
        } catch(FileException e) {
            log(LogLevel.ERROR, "could not save config");
        }
    }

    void startListener() {
        if(serverConfig.onboarded) {
            db = new RedisDatabaseDriver(serverConfig.redisHost, serverConfig.redisPort);
        //    keyStore = db.getClient().getDatabase(4); 
        }
        else {
		log(LogLevel.INFO, "please onboard the orchestrator");
        }

    }

    this(string _configPath = "./config.json") {

	ResourceIdentifier logEngine = g_ResourceManager.instantiateResource("LogEngine");

	shared(Resource) _l = g_ResourceManager.getResource(logEngine);

	_l.useResource();
	{
		LogEngine l = cast(LogEngine)_l;
		l.logFile = "scylla.log";

		_l.deploy();
	}
	_l.releaseResource();

	log(LogLevel.INFO, "arcus starting up..");

	configPath = _configPath;

        loadConfig(configPath);

	root = new RootDriver();
        vmServer = new Kintsugi();

	//resourceMgr.registerClass("NIC", &NICResource.instantiate());
    }

    
};

