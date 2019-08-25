module zephyr.core.server;
import zephyr.models.config;
import vibe.vibe;
import bap.core.server;
import bap.core.db;
import bap.core.redis;
import asdf;
import zephyr.models.event;
import zephyr.models.auth_info;
import zephyr.models.node_target;
import zephyr.models.user_target;
import zephyr.models.vps_target;

mixin template GrabEvent(T) {
	T e;
	auto _eventGrabber = () @trusted {
		try {
			e = deserialize!T(data);
		} catch (Exception e) {
			logError("exception: %s", e.msg);
			return "no";
		} catch (AssertError e) {
			logError("%s", e.msg);
			return "no";
		}
		return "yes";
	}();
}

class ZephyrServer {
	private {
		HTTPListener listener;
		RedisDatabaseDriver _db;
		RedisDatabase apiKeyStore;
		ZephyrConfig serverConfig;
		string configPath;
	}

	bool canFindAPIKey(string apiKey) nothrow {
		try {
			if (apiKeyStore.exists(apiKey)) {
				return true;
			}
		} catch (Exception e) {
			logError("caught an exception while trying to find API key: %s", e.msg);
		}
		return false;
	}

	User pullFromAPIKey(string apiKey) nothrow {
		if (canFindAPIKey(apiKey)) {
			try {
				string keyJSON = apiKeyStore.request!string("json.get", apiKey);

				AuthInfo r = keyJSON.deserialize!AuthInfo();

				auto u = _db.getUser(r.user);

				if (!u.isNull) {
					return u;
				} else {
					assert(0, "user was null????");
				}
			} catch (Exception e) {
				assert(0, e.msg);
			}
		} else {
			assert(0, "could not find api key");
		}
	}

	import bap.core.node;

	class ZephyrREST : ServerREST {
		@path("/api/v1/admin/node/:action")
		@method(HTTPMethod.POST)
		nothrow string postAdminNodeAction(string api_key, string data, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.admin) {
				return "NO_PERMS";
			}

			mixin GrabEvent!(NodeTarget);

			if (_eventGrabber == "no") {
				return _eventGrabber;
			}

			if (_action == "delete") {
				if (e.hostname == "") {
					return "BLANK_HOST";
				} else {
					auto _n = _db.getNode(e.hostname);

					if (!_n.isNull) {
						Node n = _n;

						foreach (vps; n.deployedVPS) {
							logInfo("delete vps %d", vps);
						}

						_db.deleteNode(e.hostname);
						return "OK";
					}
				}
			} else if (_action == "create") {
				Node n;
				if (e.hostname == "") {
					return "BLANK_HOST";
				}

				if (e.port == 0) {
					return "BLANK_PORT";
				}

				if (e.ipAddress == "") {
					return "BLANK_IP";
				}

				n.name = e.hostname;
				n.host = e.hostname;
				n.port = e.port;
				n.initialized = false;
				_db.insertNode(n);

				return "OK";
			}

			return "UNIMPLEMENTED";

		}

		@path("/api/v1/admin/node/:target/:action")
		@method(HTTPMethod.POST)
		nothrow string postAdminNodeTarget(string api_key, string data,
				string _target, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.admin) {
				return "NO_PERMS";
			}
			mixin GrabEvent!(NodeTarget);

			if (_eventGrabber == "no") {
				return _eventGrabber;
			}

			return "UNIMPLEMENTED";

		}

		@path("/api/v1/admin/user/:action")
		@method(HTTPMethod.POST)
		nothrow string postAdminUserAction(string api_key, string data, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.admin) {
				return "NO_PERMS";
			}

			mixin GrabEvent!(UserTarget);

			if (_eventGrabber == "no") {
				return _eventGrabber;
			}

			if (_action == "create") {
				if (e.username == "") {
					return "BLANK_USERNAME";
				}

				if (e.email == "") {
					return "BLANK_EMAIL";
				}

				if (e.realName == "") {
					return "BLANK_NAME";
				}

				if (e.picture == "") {
					return "BLANK_PICTURE";
				}

				User newUser;
				newUser.username = e.username;
				newUser.name = e.realName;
				newUser.email = e.email;
				newUser.profilePicURL = e.picture;
				newUser.admin = e.admin;
				newUser.resetPassword = true;

				auto t = _db.getUser(e.username);
				if (t.isNull) {
					_db.insertUser(newUser);
					return "OK";
				} else {
					return "DUPLICATE_USERNAME";
				}

			} else if (_action == "delete") {
				if (e.username == "") {
					return "BLANK_USERNAME";
				}

				if (_db.deleteUser(e.username)) {
					return "OK";
				} else {
					return "ERROR";
				}

			} else if (_action == "update") {
				if (e.username == "") {
					return "BLANK_USERNAME";
				}

				auto _t = _db.getUser(e.username);
				if (_t.isNull) {
					return "NO_USER";
				}

				User t = _t;

				if (e.email != "") {
					t.email = e.email;
				}

				if (e.realName != "") {
					t.name = e.realName;
				}

				if (e.picture != "") {
					t.profilePicURL = e.picture;
				}

				t.admin = e.admin;

				_db.insertUser(t);

				return "OK";

			}

			return "UNIMPLEMENTED";

		}

		@path("/api/v1/admin/user/:target/:action")
		@method(HTTPMethod.POST)
		nothrow string postAdminUserTarget(string api_key, string data,
				string _target, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.admin) {
				return "NO_PERMS";
			}

			mixin GrabEvent!(UserTarget);

			if (_eventGrabber == "no") {
				return _eventGrabber;
			}

			return "UNIMPLEMENTED";
		}

		@path("/api/v1/admin/vps/:action")
		@method(HTTPMethod.POST)
		nothrow string postAdminVPSAction(string api_key, string data, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.admin) {
				return "NO_PERMS";
			}

			mixin GrabEvent!(VPSTarget);

			if (_eventGrabber == "no") {
				return _eventGrabber;
			}

			if (_action == "create") {
				if (e.node == "") {
					return "BLANK_NODE";
				}

				auto _n = _db.getNode(e.node);
				if (_n.isNull) {
					return "NO_NODE";
				}

				Node n = _n;

				if (e.hostname == "") {
					return "BLANK_HOSTNAME";
				}

				if (e.cpuCount == 0) {
					return "INVALID_CPU";
				}

				/*
                   Linux needs **AT LEAST** 256 mb of ram
                */

				if (e.ramSize <= 256) {
					return "INVALID_RAM";
				}

				if (e.drives.length != e.driveSizes.length) {
					return "INVALID_DISKS";
				}

				bool atLeastOneRoot = false;

				foreach (i, drive; e.drives) {
					if (e.driveSizes[drive.driveID] <= 10) {
						return "BAD_DRIVE";
					}

					if (drive.isRootDevice) {
						if (atLeastOneRoot) {
							return "BAD_DRIVE";
						}

						atLeastOneRoot = true;
					}

				}

				if (e.diskTemplate == "") {
					return "BLANK_DISK_TEMPLATE";
				}

				if (e.targetUser == "") {
					return "BLANK_USER";
				}

				VPS v;

				/*
                    From the disk template, the VPS will have it's root disk path
                    determined, and we cannot set it while on the server end.
                    It should be set to blank, as it will be overwritten later.
                */

				import std.uuid;

				v.state = VPS.State.provisioned;

				v.drives = e.drives;
				v.driveSizes = e.driveSizes;
				v.osTemplate = e.diskTemplate;
				v.name = e.hostname;
				v.node = e.node;
				try {
					v.uuid = randomUUID().toString();
				} catch (Exception e) {
					logError("could not generate UUID?");
					return "UUID_GEN_ERROR";
				}
				v.owner = e.targetUser;
				v.config.htEnabled = true;
				v.config.memSizeMib = e.ramSize;
				v.config.vcpuCount = e.cpuCount;

				if (_db.getVPS(v.uuid).isNull) {
					_db.insertVPS(v);
				} else {
					return "COLLISION";
				}

				return v.uuid;

			}

			return "UNIMPLEMENTED";

		}

		@path("/api/v1/admin/vps/:target/:action")
		@method(HTTPMethod.POST)
		nothrow string postAdminVPSTarget(string api_key, string data,
				string _target, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.admin) {
				return "NO_PERMS";
			}

			mixin GrabEvent!(VPSTarget);

			if (_eventGrabber == "no") {
				return _eventGrabber;
			}

			return "UNIMPLEMENTED";

		}

		@path("/api/v1/user/:action")
		@method(HTTPMethod.POST)
		nothrow string postUserAction(string api_key, string data, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (_action == "vps_list") {
				string v = "{'vps_list': [";

				foreach (i, s; requester.servers) {
					v ~= "'" ~ s ~ "'";
					if (i != requester.servers.length - 1) {
						v ~= ", ";
					}
				}
				v ~= "]}";

				return v;
			}

			mixin GrabEvent!(UserTarget);

			if (_eventGrabber == "no") {
				return _eventGrabber;
			}

			if (_action == "reset_password") {
				if (e.newPassword == "") {
					return "BLANK_PASSWORD";
				} else {
					import dauth;
					import std.string : replace;

					try {
						Password p = toPassword(e.newPassword.dup);
						requester.hashedPassword = makeHash(p).toCryptString().replace("/", "^");
						_db.insertUser(requester);
					} catch (Exception e) {
						logError("could not set new password");
						return "NOT_OK";
					}

					return "OK";
				}

			} else if (_action == "update_profile") {

				if (e.email != "") {
					requester.email = e.email;
				}

				if (e.realName != "") {
					requester.name = e.realName;
				}

				if (e.picture != "") {
					requester.profilePicURL = e.picture;
				}

				_db.insertUser(requester);

				return "OK";
			}

			return "UNIMPLEMENTED";
		}

		@path("/api/v1/vps/:target")
		@method(HTTPMethod.GET)
		nothrow string getVPS(string api_key, string _target) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.servers.canFind(_target)) {
				return "NO_ACCESS";
			}

			auto _v = _db.getVPS(_target);
			if (_v.isNull) {
				assert(0, "Got a VPS that shouldn't be accessible.");
			}

			import bap.models.vps;

			VPS v = _v;

			string ret;
			try {
				ret = v.stringify;
			} catch (Exception e) {
				ret = "ERR_EXCEPTION";
				logError("exception: %s", e.msg);
			}

			return ret;
		}

		@path("/api/v1/vps/:target/:category")
		@method(HTTPMethod.GET)
		nothrow string getVPSInfo(string api_key, string data, string _target, string _category) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);
			if (!requester.servers.canFind(_target)) {
				return "NO_ACCESS";
			}

			auto _v = _db.getVPS(_target);
			if (_v.isNull) {
				assert(0, "Got a VPS that shouldn't be accessible.");
			}

			import bap.models.vps;

			VPS v = _v;

			if (_category == "disk") {

			} else if (_category == "cpu") {

			} else if (_category == "ram") {

			} else if (_category == "template") {

			} else if (_category == "config") {

			} else if (_category == "node") {

			}

			return "UNIMPLEMENTED";
		}

		@path("/api/v1/vps/:target/:action")
		@method(HTTPMethod.POST)
		nothrow string postVPSAction(string api_key, string data, string _target, string _action) {
			if (!canFindAPIKey(api_key)) {
				return "AUTH_FAIL";
			}

			User requester = pullFromAPIKey(api_key);

			if (!requester.servers.canFind(_target)) {
				return "NO_ACCESS";
			}

			auto _v = _db.getVPS(_target);
			if (_v.isNull) {
				assert(0, "Got a VPS that shouldn't be accessible.");
			}

			import bap.models.vps;

			VPS v = _v;

			if (_action == "start") {
				logInfo("got %s action", _action);
				return "OK";
			} else if (_action == "shutdown") {
				logInfo("got %s action", _action);
				return "OK";

			} else if (_action == "stop") {
				logInfo("got %s action", _action);
				return "OK";

			} else if (_action == "reboot") {
				logInfo("got %s action", _action);
				return "OK";

			} else if (_action == "redeploy") {
				logInfo("got %s action", _action);

				mixin GrabEvent!(VPSTarget);

				if (_eventGrabber == "no") {
					return _eventGrabber;
				}
				return "OK";
			} else if (_action == "mmds") {

			}

			return "UNIMPLEMENTED";
		}

	}

	void loadConfig(string path = "./config.json") {
		import std.file;
		import asdf;

		if (exists(path)) {
			string c = cast(string) read(path);
			serverConfig = c.deserialize!ZephyrConfig;
		} else {
			serverConfig = ZephyrConfig();
			saveConfig(path);
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
			logError("could not save config");
		}
	}

	void startListener() {
		auto settings = new HTTPServerSettings;
		settings.port = 8082;
		settings.bindAddresses = ["0.0.0.0"];
		settings.options = HTTPServerOption.reusePort;

		auto router = new URLRouter;
		router.registerRestInterface(new ZephyrREST());

		_db = new RedisDatabaseDriver(serverConfig.redisHost, serverConfig.redisPort);

		apiKeyStore = _db.getClient().getDatabase(4);

		listener = listenHTTP(settings, router);

		foreach (user; _db.getAllUsers()) {
			if (user.apiKey == "") {
				logWarn("user %s has no api key!", user.username);
				logWarn("generating new one for them and assigning scope");

				import dauth : randomToken;

				user.apiKey = randomToken(64);

				AuthInfo key;
				if (user.admin) {
					key.scopes = ["*"];
				}
				key.scopes ~= ["user." ~ user.username ~ ".*"];
				key.user = user.username;

				_db.insertUser(user);
				apiKeyStore.request!string("json.set", user.apiKey, ".", key.stringify);

			}
		}
	}

	this(string configPath) {
		logInfo("== Zephyr API server booting up ==");

		loadConfig(configPath);
		logInfo("== Loaded config ==");
	}
}
