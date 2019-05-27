module scylla.core.server;
import vibe.d;
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
import scylla.core.resource_manager;
import asdf;

class ScyllaServer {
    private {
        ScyllaConfig serverConfig;
        RedisDatabaseDriver db;
        RedisDatabase keyStore;
	ResourceManager rem;
        Kintsugi vmServer;

        string configPath;
    };
    

    import std.file;

    void loadConfig(string path = "./config.json") {
        import std.file, std.json, jsonizer;
        if(exists(path)) {
            string c = cast(string)read(path);
            JSONValue _c = parseJSON(c);
            serverConfig = fromJSON!ScyllaConfig(_c);
        }
        else {
            serverConfig = ScyllaConfig();
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
            logError("could not save config");
        }
    }
    void startListener() {
        if(serverConfig.onboarded) {
            db = new RedisDatabaseDriver(serverConfig.redisHost, serverConfig.redisPort);
            keyStore = db.getClient().getDatabase(4); 
        }
        else {
            logInfo("server has not been onboarded.. please initialize it.");
        }

    }

    this(string _configPath = "./config.json") {
        configPath = _configPath;
        vmServer = new Kintsugi();
        loadConfig(configPath);
    }
};

