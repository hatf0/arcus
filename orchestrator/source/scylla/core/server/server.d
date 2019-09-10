module scylla.core.server.server;
import std.stdio;
import bap.core.node;
import bap.model;
import bap.core.redis;
import bap.core.db;
import scylla.models.config.scylla;
import vibe.web.auth;
import vibe.http.session;
import vibe.web.web : noRoute;
import scylla.core.server.kintsugi;
import bap.core.utils;
import asdf;
import bap.core.resource_manager;

static string productName = "Arcus";
static string versionNumber = "v0.0.1 PreAlpha | Orchestrator";

static string productString = productName ~ " " ~ versionNumber;

class ScyllaServer {
	private {
		ScyllaConfig serverConfig;
		RedisDatabaseDriver db;
		Kintsugi vmServer;

		string configPath;
	};

	void loadConfig(string path = "./config.json") {
		import std.file, std.json;

		if (exists(path)) {
			string c = cast(string) read(path);
			serverConfig = c.deserialize!ScyllaConfig();
			log(LogLevel.INFO, "loaded arcus config from " ~ path);
		} else {
			serverConfig = ScyllaConfig();
			log(LogLevel.INFO, "creating new config");
			saveConfig(configPath);
		}
	}

	void saveConfig(string path = "") {
		if (path == "") {
			path = configPath;
		}

		import std.file;

		try {
			write(path, serverConfig.stringify);
		} catch (FileException e) {
			log(LogLevel.ERROR, "could not save config");
		}
	}

	void startListener() {
		if (serverConfig.redisHost != "") {
			db = new RedisDatabaseDriver(serverConfig.redisHost, serverConfig.redisPort);
			//    keyStore = db.getClient().getDatabase(4); 
		}

	}

	void validateConfig() {
		if (serverConfig.redisHost == "") {
			log(LogLevel.ERROR, "redis host is blank. Please fill in.");
		}

		if (serverConfig.vpsStoragePath == "") {
			log(LogLevel.INFO, "storage path is blank, assuming typical location");
		}

		if (serverConfig.vpsImagePath == "") {
			log(LogLevel.INFO, "image path is blank, assuming typical location");
		}

		if (serverConfig.listenAddress == "") {
			log(LogLevel.INFO, "listen address is blank, assuming listen on all addresses");
		}
	}

	this(string _configPath = "./config.json") {

		ResourceIdentifier logEngine = g_ResourceManager.instantiateResource!(LogEngine);

		auto _l = g_ResourceManager.getResource!(LogEngine)(logEngine);

		auto l = _l.useResource();
		{
			l.logFile = "scylla.log";
		}
		_l.releaseResource(l);

		_l.deploy();

		import vibe.core.core : lowerPrivileges;

		lowerPrivileges("nobody", "kvm");

		import core.thread;
		Thread.sleep(500.msecs);
		log(LogLevel.INFO, "arcus starting up..");

		configPath = _configPath;

		loadConfig(configPath);

		vmServer = new Kintsugi();
	}

};
