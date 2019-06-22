module scylla.core.server;
import std.stdio;
import bap.core.node;
import bap.model;
import bap.core.redis;
import bap.core.db;
import scylla.models.config;
import vibe.web.auth;
import vibe.http.session;
import vibe.web.web : noRoute;
import scylla.core.kintsugi;
import scylla.core.utils;
import asdf;
import scylla.core.resource_manager;

class ScyllaServer {
    private {
        ScyllaConfig serverConfig;
        RedisDatabaseDriver db;
	LogEngine _log;
	ResourceManager resourceMgr;
        Kintsugi vmServer;

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
        configPath = _configPath;
	_log = new LogEngine("", LogLevel.INFO);

	log(LogLevel.INFO, "arcus starting up..");
        loadConfig(configPath);

        vmServer = new Kintsugi();
	resourceMgr = new ResourceManager();

	//resourceMgr.registerClass("NIC", &NICResource.instantiate());
    }

    
};

