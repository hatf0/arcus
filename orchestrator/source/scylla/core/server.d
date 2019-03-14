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
import asdf;

class ScyllaServer {
    private {
        ScyllaConfig serverConfig;
        HTTPListener listener;
        RedisDatabaseDriver db;
        RedisDatabase keyStore;
        Kintsugi vmServer;
        string configPath;
    };

    struct WebSocketEvent {
        @serializationRequired
        @serializationKeys("event") string event;
        
        @serializationKeys("data") string data;
        
        @serializationKeys("id") string widgetID;
        @serializationKeys("class") string widgetClass;
        @serializationKeys("text") string widgetText;
    }

    bool hasAccess(string comm_key, string uuid) {
            if(comm_key == serverConfig.communicationKey) {
                return true;
            }

            if(keyStore.exists(comm_key)) {
                string targetUUID = keyStore.get!string(comm_key);
                logInfo("got target uuid: " ~ targetUUID ~ ", comparing to uuid: " ~ uuid);
                if(targetUUID == uuid) {
                    return true;
                }
                return false;
            }
            return false;
    }

    class ScyllaREST : NodeREST {
        string postOnboard(OnboardData data) {
            writeln(serverConfig.onboarded, " is state");
            if(serverConfig.onboarded) {
                return "BAD";
            }
            else {
                writeln(data);
                serverConfig.onboarded = true;
                serverConfig.communicationKey = data.communication_key;
                serverConfig.nodeName = data.node_name;
                serverConfig.redisHost = data.redis_host;
                serverConfig.redisPort = data.redis_port;
                serverConfig.redisPassword = data.redis_password;

                logInfo("we have been onboarded!");

                // Launch a new Redis connection using the credentials we got..
                Nullable!Node us;
                try {
                    db = new RedisDatabaseDriver(data.redis_host, data.redis_port);
                    logInfo("attempting to communicate to redis..");
                    us = db.getNode(serverConfig.nodeName);
                } catch(Exception e) {
                    logError("fail!");
                    return "BAD";
                }

                logInfo("grabbing our node info from redis..");
                if(!us.isNull) {
                    Node ourNode = us;
                    ourNode.initialized = true;
                    logInfo("updating our status so redis knows we're alive and well");
                    if(!db.insertNode(ourNode)) {
                        logError("inserting node back into redis failed");
                    }
                    
                    logInfo("restarting http listener..");
                    listener.stopListening();
                    startListener();
                    logInfo("good to go!");

                }
                else {
                    logError("something has gone horribly wrong?");
                    return "BAD";
                }

                saveConfig();
                return "OK";
            }
        }

        string postPing() {
            return "PONG";
        }

        string getVersion() {
            return "OK";
        }

        @path("vps/new")
        string postNewVPS(string key, VPS vps) {
            if(!serverConfig.onboarded) {
                logInfo("got a request without being initialized");
                return "NOT_ONBOARDED";
            }
            import std.file;
            if(key == serverConfig.communicationKey) {
                if(vps.state == VPS.State.provisioned) {
                    if(vps.osTemplate == "ubuntu-1804") {
                        import std.process, std.format;
                        string disk_path = "/srv/scylla/disk_images/" ~ vps.uuid;
                        string kernel_path = "/srv/scylla/boot_images/" ~ vps.uuid;
                        if(!exists(disk_path)) {
                            mkdir(disk_path);
                        }

                        if(!exists(kernel_path)) {
                            mkdir(kernel_path);
                        }

                        auto a = executeShell("cp /srv/scylla/disk_images/generic/ubuntu " ~ disk_path);
                        writeln(a.output);
                        auto b = executeShell("cp /srv/scylla/boot_images/generic/ubuntu " ~ kernel_path);
                        writeln(b.output);

                        auto c = executeShell(format!"truncate -s %dG %s"(vps.driveSizes["rootfs"], disk_path ~ "/ubuntu")); 
                        writeln(c.output);

                        writeln(executeShell("e2fsck -f -y " ~ disk_path ~ "/ubuntu").output);
                        writeln(executeShell("resize2fs " ~ disk_path ~ "/ubuntu").output);

                        vps.boot.kernelImagePath = kernel_path ~ "/ubuntu";
                        import firecracker_d.models.drive;

                        Drive _d;
                        _d.driveID = "rootfs";
                        _d.pathOnHost = disk_path ~ "/ubuntu";
                        _d.isRootDevice = true;
                        _d.isReadOnly = false;
                        vps.drives ~= _d; 
                    }
                    else {
                        writeln("unknown template ", vps.osTemplate);
                    }
                }
                else {
                    writeln("vps was not in state expected..");
                }
                vmServer.spawnVM(vps);

                vps.ip_address = vmServer.getIPAddress(vps.uuid).mainIP;
                vps.state = VPS.State.deployed;
                db.insertVPS(vps);
                return "OK";
            }
            return "NO";
        }

        @path("vps/:action")
        string postVPS(string key, string uuid, string _action) {
            if(!serverConfig.onboarded) {
                logInfo("got a request without being initialized");
                return "NOT_ONBOARDED";
            }
            if(hasAccess(key, uuid)) { 
                if(_action == "auth_key") {
                    import dauth;
                    string newAuthKey = randomToken(48);
                    db.getClient().getDatabase(3).request!string("set", newAuthKey, uuid, "EX", 100);
                    logInfo("got auth key request for uuid: " ~ uuid);
                    logInfo("sending auth key: " ~ newAuthKey);
                    return newAuthKey;
                }

                logInfo("got request for " ~ uuid);
                return "OK";
            }
            return "NO";
        }

        
    };

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

    void addCORS(HTTPServerRequest req, HTTPServerResponse res) {
        res.headers["Access-Control-Allow-Origin"] = "*";
    }

    void webSocketHandler(scope WebSocket sock) nothrow {
        import std.json;
        import std.stdio;
        import core.time;
        import core.exception;
        import std.exception;

        try {
            sock.send(asdf.serializeToJson(WebSocketEvent("hello")));
        }
        catch(Exception e) {
            logError("failed to send socket hello");
            return;
        }

        string vm_id;
        string vm_key;

        try {
            if(!sock.waitForData(dur!"seconds"(10))) {
                logInfo("Closed connection because no authentication was sent.");

                sock.send(asdf.serializeToJson(WebSocketEvent("timeout")));
                sock.close();
            }
            else {
                string key = sock.receiveText;
                try {
                    JSONValue n = parseJSON(key);
                    vm_id = n["id"].str;
                    vm_key = n["key"].str;
                    if(!hasAccess(vm_key, vm_id)) {
                        logInfo("attempt to auth with key: " ~ vm_key);
                        sock.send(asdf.serializeToJson(WebSocketEvent("failed_auth")));
                        sock.close();
                    }
                    else {
                        sock.send(asdf.serializeToJson(WebSocketEvent("success_auth")));
                        keyStore.del([vm_key]);
                    }
                }
                catch(JSONException e) {
                    sock.send(`{"event": "error"}`);
                    sock.close();
                }
            }
        }
        catch(Exception e) {
            logError("got an exception while processing authentication.");
        }
        string lastUpdate_icon = "";
        string lastUpdate_text = "";
        string lastUpdate_ip = "";
        bool sockConnected = false;
        try {
            sockConnected = sock.connected;
        } catch(Exception e) {
            logError("could not get status of socket?");
            return;
        }
        while(sockConnected) {
            string getStatus() {
                return vmServer.getInstanceState(vm_id);
            }

            string status;
            collectException(getStatus, status);
            bool availableForRead = false;
            try {
                availableForRead = sock.dataAvailableForRead;
            } catch(Exception e) {
                logError("cannot determine if socket has anything available for reading..");
                return;
            }
            if(availableForRead) {
                string data;
                try {
                    data = sock.receiveText;
                } catch(Exception e) {
                    logError("could not receive text from websocket");
                    return;
                }
                logInfo("got json object: " ~ data);
                WebSocketEvent eval;
                WebSocketEvent clEvent;
                try {
                    clEvent = data.deserialize!WebSocketEvent();
                } catch(DeserializationException e) {
                    logError("could not deserialize event");
                    return;
                } catch(Exception e) {
                    logError("generic exception caught while attempting to deserialize event");
                    return;
                }

                try {
                    eval.data = `$.notify({message:'Action performed successfully.'},{type:'success',showProgressbar:false});`;
                    if(clEvent.event == "start") {
                        logInfo("got start notification with status: " ~ status);
                        if(status != "online") {
                            logInfo("sending start request for vm_id: " ~ vm_id);
                            vmServer.startVM(vm_id);
                        }
                    }
                    else if(clEvent.event == "restart") {
                        vmServer.reboot(vm_id);
                    }
                    else if(clEvent.event == "shutdown") {
                        vmServer.gracefulShutdown(vm_id);
                    }
                    else {
                        eval.data = `$.notify({message:'Unknown event type.'},{type:'error',showProgressbar:false});`;
                    }
                    sock.send(asdf.serializeToJson(eval));
                }
                catch(Exception e) {
                    logError("caught exception!! %s", e.msg);
                    return;
                }
            }

            logDebug("pushing events to array");
            WebSocketEvent[] events;
            events ~= WebSocketEvent("update", null, "info-widget-icon"); 
            events ~= WebSocketEvent("update", null, "info-widget-text");
            events ~= WebSocketEvent("update", null, "ip-address");
            Nullable!VPS v = db.getVPS(vm_id);
            if(!v.isNull) {
                VPS vps = v;
                import scylla.core.firecracker : IPInfo;
                try {
                    IPInfo ip = vmServer.getIPAddress(vm_id);
                    events[2].widgetText = ip.mainIP;
                } catch(Exception e) {
                    logError("could not get ip address for node");
                }

                if(status == "online") {
                //    string[] latestLogs = vmServer.getLogs(vm_id);
                    events[0].widgetClass = "info-box-icon bg-aqua";
                    events[1].widgetText = "ONLINE";
                    if(v.state != VPS.State.running) {
                        v.state = VPS.State.running;
                        db.insertVPS(v);
                    }
                }
                else {
                    events[0].widgetClass = "info-box-icon bg-red";
                    events[1].widgetText = "OFFLINE";
                    if(v.state != VPS.State.shutoff) {
                        v.state = VPS.State.shutoff;
                        db.insertVPS(v);
                    }
                }
            }
            try {
                logDebug("sending");
                foreach(event; events) {
                    sock.send(asdf.serializeToJson(event));
                }
                sleep(5.seconds);
                sockConnected = sock.connected;
            } catch(Exception e) {
                logError("could not get status of socket?");
                return;
            }
        }
    }

    bool spoolAllVMs() {
        if(serverConfig.onboarded) {
            foreach(vps; db.getAllVPS()) {
                if(vps.node == serverConfig.nodeName) {
                    vmServer.spawnVM(vps);
                    vps.state = VPS.State.shutoff;
                    vps.ip_address = vmServer.getIPAddress(vps.uuid).mainIP;
                    db.insertVPS(vps);
                }
            }
            return true;
        }
        return false;
    }


    void startListener() {
        auto settings = new HTTPServerSettings;
        settings.port = 8081;
        settings.bindAddresses = ["0.0.0.0"];
        settings.options = HTTPServerOption.reusePort;

        auto router = new URLRouter;
        router.any("*", &addCORS)
              .get("/ws", handleWebSockets(&webSocketHandler));
        router.registerRestInterface(new ScyllaREST());

        if(serverConfig.onboarded) {
            db = new RedisDatabaseDriver(serverConfig.redisHost, serverConfig.redisPort);
            settings.sessionStore = new MemorySessionStore();
            keyStore = db.getClient().getDatabase(3); 
            spoolAllVMs();
        }
        else {
            logInfo("server has not been onboarded.. please initialize it.");
        }

        listener = listenHTTP(settings, router);

    }

    this(string _configPath = "./config.json") {
        configPath = _configPath;
        vmServer = new Kintsugi();
        loadConfig(configPath);
    }
};

