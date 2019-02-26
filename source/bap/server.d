module bap.server;
import bap.model;
import vibe.d;
import std.concurrency;
import bap.core.db;
import bap.core.redis;
import bap.core.server;

class BAPServer : Server {
    private { 
        Widget[][string] widgets;
        URLRouter router;
        DatabaseDriver db;

        HTTPFileServerSettings fileSettings;
        HTTPServerSettings httpSettings;
        HTTPListener listener;

        Sidebar[][string][string] sectionEntries;
        string[string][string] sectionIcons;

        string[string] nodes;

        string redis_host;
        ushort redis_port;
        string redis_password;

        string generateAllSidebar() {
            string ret = "";
            foreach(ca; sectionEntries.keys) {
                ret ~= generateSidebar(ca);
            }
            return ret;
        }

        string generateSidebars(string[] bars) {
            string ret = "";
            foreach(ca; bars) {
                ret ~= generateSidebar(ca);
            }
            return ret;
        }

        string generateSidebar(string category) {
            if(category in sectionEntries) {
                    import diet.html;
                    Sidebar[][string] entries = sectionEntries[category]; 
                    import std.array : appender;
                    import std.conv : to;
                    auto dst = appender!string();
                    string[string] _s = sectionIcons[category].dup;
                    dst.compileHTMLDietFile!("generic/sidebar_entry.dt", entries, _s, category);

                    return to!string(dst.data);
            }
            return "";
        }


        /* This is the ugliest function in the world. I WOULD REALLY REALLY LIKE TO PORT THE MAJORITY OF THE LOGIC
           ELSEWHERE BUT FUCK IT
        */

        void pageRenderer(HTTPServerRequest req, HTTPServerResponse res, string templateName = "dashboard.dt") {
            User user;
            string lastError;
            string authKey;
            VPS vps;
            if(req.session) {
                user = this.getFromSession(req);
                lastError = req.session.get!string("last_error");
                req.session.set("last_error", "ERR_SUCCESS");
                if(user.resetPassword) {
                    res.render!("password_reset.dt", lastError);
                    return;
                }

                if(templateName[0..3] == "vps") {
                    import std.algorithm.searching;
                    if(user.servers.canFind(req.params["vm_id"])) {
                      Nullable!VPS vv = db.getVPS(req.params["vm_id"]);
                      if(!vv.isNull) {
                        vps = vv;
                      }
                      else {
                        assert(0, "VM was null?");
                      }

                      logInfo("getting node " ~ vps.node);
                      Nullable!Node node = db.getNode(vps.node);
                      if(node.isNull) {
                        req.session.set("last_error", "Your node appears to be down. Contact your administrator.");
                        res.redirect("/");
                        return;
                      }
                      import std.format;
                      string url = format!"http://%s:%s/"(node.host, node.port);
                      logInfo("connecting to " ~ url);
                      try {
                        auto cl = new RestInterfaceClient!NodeREST(url);
                        authKey = cl.postVPS(node.communicationKey, req.params["vm_id"], "auth_key");
                        if(authKey == "NO") {
                          logError("got non-OK message for node '" ~ vps.node ~ "', consider investigating");
                          req.session.set("last_error", "The node '" ~ vps.node ~ "' failed to respond to our authentication request. Contact your administrator.");
                          res.redirect("/");
                        }
                      }
                      catch(Exception e) {
                        logInfo("caught exception: " ~ e.msg);
                        req.session.set("last_error", "The node '" ~ vps.node ~ "' appears to be down. Contact your administrator.");
                        res.redirect("/");
                        return;
                      }

                    }
                    else {
                      req.session.set("last_error", "ERR_NO_PERMS");
                      res.redirect("/");
                      return;
                    }
                }
            }
            
                

            string sidebarContents;
            if(user.admin) {
              if(templateName[0..5] == "admin") {
                sidebarContents = generateSidebars(["General", "Admin"]);
              }
              else if(templateName == "dashboard.dt") {
                  sidebarContents = generateSidebars(["General", "Resources"]);
              }
              else {
                sidebarContents = generateSidebars(["Management", "Resources"]);
              }
            }
            else if(templateName == "dashboard.dt") {
                sidebarContents = generateSidebars(["General", "Resources"]);
            }
            else {
              sidebarContents = generateSidebars(["Management", "Resources"]);
            }

            Server serverInterface = this;
            switch(templateName) {
              case "dashboard.dt":
                res.render!("dashboard.dt", user, lastError, sidebarContents, serverInterface, templateName);
                break;
              case "vps/dashboard.dt":
                res.render!("vps/dashboard.dt", user, lastError, sidebarContents, serverInterface, templateName, vps, authKey);
                break;
              case "vps/disks.dt":
                res.render!("vps/disks.dt", user, lastError, sidebarContents, serverInterface, templateName, vps, authKey);
                break;
              case "vps/advanced.dt":
                res.render!("vps/advanced.dt", user, lastError, sidebarContents, serverInterface, templateName, vps, authKey);
                break;
              case "vps/network.dt":
                res.render!("vps/network.dt", user, lastError, sidebarContents, serverInterface, templateName, vps, authKey);
                break;
              case "vps/redeploy.dt":
                res.render!("vps/redeploy.dt", user, lastError, sidebarContents, serverInterface, templateName, vps, authKey);
                break;
              case "vps/statistics.dt":
                res.render!("vps/statistics.dt", user, lastError, sidebarContents, serverInterface, templateName, vps, authKey);
                break;
              case "admin/dashboard.dt":
                res.render!("admin/dashboard.dt", user, lastError, sidebarContents, serverInterface, templateName);
                break;
              case "admin/nodes.dt":
                res.render!("admin/nodes.dt", user, lastError, sidebarContents, serverInterface, templateName);
                break;
              case "admin/users.dt":
                res.render!("admin/users.dt", user, lastError, sidebarContents, serverInterface, templateName);
                break;
              case "admin/vms.dt":
                res.render!("admin/vms.dt", user, lastError, sidebarContents, serverInterface, templateName);
                break;
              default:
                break;
            }
        }

        void verifyLoggedIn(HTTPServerRequest req, HTTPServerResponse res) {
            if(!req.session)
                res.redirect("/");
        }

        void verifyAdmin(HTTPServerRequest req, HTTPServerResponse res) {
            if(!req.session)
                res.redirect("/");
            
            User user;
            user = this.getFromSession(req);

            if(!user.admin) {
                req.session.set("last_error", "ERR_NO_PERMS");
                res.redirect("/");
            }
            
        }

        void index(HTTPServerRequest req, HTTPServerResponse res) {
            if(req.session) {
                res.redirect("/general/dashboard");
            }
            int loggedOut = 0;

            res.render!("index.dt", loggedOut);
        }

        void login(HTTPServerRequest req, HTTPServerResponse res) {
            if(req.session) {
                res.redirect("/general/dashboard");
                return;
            }

            enforceHTTP("username" in req.form && "password" in req.form, 
    HTTPStatus.badRequest, "Missing username/password..");

            if(db.authenticateUser(req.form["username"], req.form["password"])) {
              auto session = res.startSession();
              session.set("logged_out", 0);
              session.set("last_error", "ERR_SUCCESS");
              session.set("user", req.form["username"]);
              res.redirect("/general/dashboard");
            }
            else {
              int loggedOut = 3;
              res.render!("index.dt", loggedOut);
            }
        }

        void logout(HTTPServerRequest req, HTTPServerResponse res) {
            res.terminateSession();
            res.redirect("/");
        }

        void dashboard(HTTPServerRequest req, HTTPServerResponse res) {
            pageRenderer(req, res);
        }

        void vm_dashboard(HTTPServerRequest req, HTTPServerResponse res) {
            if(req.params["vm_id"] == "admin") {
              return;
            }
            debug {
              if(req.params["vm_id"] == "debug") {
                return;
              }
            }
            
            bool found = false;
            if(req.params["action"] != "dashboard") {
              pageRenderer(req, res, "vps/" ~ req.params["action"] ~ ".dt");
            }
            else {
              pageRenderer(req, res, "vps/dashboard.dt");
            }
        }

        debug {
            void debugGetHandler(HTTPServerRequest req, HTTPServerResponse res) {
              if(req.params["action"] == "add_user") {
                pageRenderer(req, res, "debug/debug-user-add.dt");
              }
              
            }
            void debugPostHandler(HTTPServerRequest req, HTTPServerResponse res) {
                
            }
        }

        void admin_panel(HTTPServerRequest req, HTTPServerResponse res) {
            pageRenderer(req, res, "admin/" ~ req.params["action"] ~ ".dt");
        }

        void admin_user_target(HTTPServerRequest req, HTTPServerResponse res) {
            if(req.params["action"] == "create") {
                logInfo("got user creation request");
                enforceHTTP("username" in req.form && "email" in req.form && "fullname" in req.form
                    && "picture" in req.form, 
                    HTTPStatus.badRequest, "Missing form..");

                string username = req.form["username"];

                string email = req.form["email"];
                string fullName = req.form["fullname"];
                string picture = req.form["picture"];
                bool admin = false;
                if("admin" in req.form) {
                    string _admin = req.form["admin"];
                    if(_admin == "on") {
                        admin = true;
                    }
                }
                logInfo("got request to create user: " ~ username);
                logInfo("\tuser's email: " ~ email);
                logInfo("\tuser's full name: " ~ fullName);
                logInfo("\tuser's picture: " ~ picture);
                logInfo("\tis user admin? " ~ (admin ? "true" : "false"));
                User _user;
                _user.username = username;
                _user.hashedPassword = "";
                _user.name = fullName;
                _user.profilePicURL = picture;
                _user.email = email;
                _user.lastLoggedIn = "Never";
                _user.resetPassword = true;
                db.insertUser(_user);

                res.writeBody("OK", 200);
            }

        }

        void admin_user_target_do(HTTPServerRequest req, HTTPServerResponse res) {

            User localUser = this.getFromSession(req);
            if(req.params["target"] == localUser.username) {
                logError("you cannot modify yourself");
                res.writeBody("FAIL", 400);
                return;
            }
            Nullable!User _user = db.getUser(req.params["target"]);
            if(!_user.isNull) {
                User user = _user;
                if(req.params["action"] == "destroy") {
                    foreach(server; user.servers) {
                        db.deleteVPS(server);
                    }

                    db.deleteUser(req.params["target"]);
                }
                res.writeBody("OK", 200);
            }
        }

        void admin_node_target(HTTPServerRequest req, HTTPServerResponse res) {
            if(req.params["action"] == "create") {
                import std.conv;
                enforceHTTP("hostname" in req.form && "ip" in req.form && "port" in req.form, 
                    HTTPStatus.badRequest, "Missing username/password..");

                Node _node;
                _node.host = req.form["ip"];
                _node.name = req.form["hostname"];
                try {
                    _node.port = to!ushort(req.form["port"]);
                }
                catch(ConvOverflowException) {
                    logError("got a port that was way too big: " ~ req.form["port"]);
                    res.writeBody("PORT_TOO_BIG", 400);
                    return;
                }
                catch(ConvException) {
                    logError("got conv exception");
                    res.writeBody("NO", 400);
                    return;
                }
                _node.initialized = false;
                db.insertNode(_node);
            }
            logInfo("got request for: " ~ req.params["action"]);
            res.writeBody("OK", 200);
        }


        void admin_node_target_do(HTTPServerRequest req, HTTPServerResponse res) {
            Nullable!Node n = db.getNode(req.params["target"]);
            if(!n.isNull) {
              Node node = n;
              if(req.params["action"] == "provision") {
                import std.format;
                string url = format!"http://%s:%s/"(node.host, node.port);

                import dauth;
                logInfo("got a provision request for node " ~ node.name);
                OnboardData datum;
                datum.redis_host = redis_host;
                datum.redis_port = redis_port;
                datum.redis_password = redis_password;
                datum.node_name = node.name;
                string securePassword = randomToken(144);
                datum.communication_key = securePassword;
                node.communicationKey = securePassword;
                db.insertNode(node); 

                try {
                  auto cl = new RestInterfaceClient!NodeREST(url);
                  if(cl.postOnboard(datum) == "OK") {
                    res.writeBody("OK", 200);
                  }
                  else {
                    res.writeBody("FAIL", 400);
                  }
                }
                catch(Exception e) {
                  logError("error while attempting to communicate with node");
                }
              }
              else if(req.params["action"] == "destroy") {
                  foreach(vps; node.deployedVPS) {
                      db.deleteVPS(vps);
                  }
                  db.deleteNode(req.params["target"]);
                  res.writeBody("OK", 200);
              }
              else {
                logInfo("got action: " ~ req.params["action"]);
              }
            }
            else {
              logInfo("got a null node");
            }
        }
        
        //node=local&hostname=test&vcpu_count=2&ram_size=1&disk_size=15&disk_template=ubuntu&user=hatf0"
        void admin_vm_target(HTTPServerRequest req, HTTPServerResponse res) {

            if(req.params["action"] == "provision") {
              enforceHTTP("node" in req.form && "hostname" in req.form && "vcpu_count" in req.form && "ram_size" in req.form && "disk_size" in req.form && "os_template" in req.form && "user" in req.form, HTTPStatus.badRequest, "One or more fields were not submitted in the form.");

              string node, hostname, user, os_template;
              uint ram_size, disk_size, vcpu_count;

              node = req.form["node"];
              hostname = req.form["hostname"];
              user = req.form["user"];
              os_template = req.form["os_template"];

              import std.regex;
              auto re = ctRegex!(`[^A-Za-z0-9.-]`);
              hostname = hostname.replaceAll(re, "");
              os_template = os_template.replaceAll(re, "");

              import core.exception;
              try {
                import std.conv;
                ram_size = to!uint(req.form["ram_size"]);
                disk_size = to!uint(req.form["disk_size"]);
                vcpu_count = to!uint(req.form["vcpu_count"]);
              } catch(Exception e) {
                res.writeBody("Numbers were not provided for numeric fields.", 200);
                return;
              }

              if(ram_size < 256) {
                res.writeBody("Expected memory value of higher then 256MiB", 200);
                return;
              }

              if(vcpu_count < 1) {
                res.writeBody("Expected vcpu count to be at least 1", 200);
                return;
              }

              if(disk_size < 10) {
                res.writeBody("Expected disk size to be at least 10GB", 200);
                return;
              }

              if(hostname == "") {
                res.writeBody("Expected a non-empty value for hostname", 200);
                return;
              }

              if(user == "") {
                res.writeBody("Expected a non-empty value for user", 200);
                return;
              }

              if(node == "") {
                res.writeBody("Expected a non-empty value for node", 200);
                return;
              }

              logInfo("got request to provision vps");
              logInfo("\tnode: " ~ node);
              logInfo("\thostname: " ~ hostname);
              logInfo("\tuser: " ~ user);
              logInfo("\tos template: " ~ os_template);
              logInfo("\tvcpu count: " ~ req.form["vcpu_count"]);
              logInfo("\tdisk size: " ~ req.form["disk_size"] ~ " gb");
              logInfo("\tram size: " ~ req.form["ram_size"] ~ " mb");

              Nullable!User _u = db.getUser(user);
              User u;

              if(!_u.isNull) {
                u = _u;
              }
              else {
                res.writeBody("Expected a valid user", 200);
                return;
              }


              VPS v;

              Nullable!Node _n = db.getNode(node);
              if(!_n.isNull) {
                import std.uuid;
                v.state = VPS.State.provisioned;
                v.platform = VPS.PlatformTypes.firecracker;
                v.osTemplate = os_template;
                v.name = hostname;
                v.uuid = randomUUID().toString();
                v.node = node;
                v.owner = user;
                v.config.htEnabled = true;
                v.config.memSizeMib = ram_size;
                v.config.vcpuCount = vcpu_count;
                v.driveSizes["rootfs"] = disk_size;
                u.servers ~= v.uuid;
                db.insertVPS(v);
                db.insertUser(u);
                Node n = _n;
                import std.format;
                string url = format!"http://%s:%s/"(n.host, n.port);
                auto cl = new RestInterfaceClient!NodeREST(url);
                cl.postNewVPS(n.communicationKey, v);
              }
            }
            res.writeBody("OK", 200);

        }

        void admin_vm_target_do(HTTPServerRequest req, HTTPServerResponse res) {
            res.writeBody("OK", 200);
        }

        void reset_password(HTTPServerRequest req, HTTPServerResponse res) {
            enforceHTTP("password-1" in req.form && "password-2" in req.form, HTTPStatus.badRequest, "No passwords submitted..");

            if(req.form["password-1"] == req.form["password-2"]) {
                import dauth, std.string;
                Password p = toPassword(req.form["password-1"].dup);
                User user = this.getFromSession(req);
                user.hashedPassword = makeHash(p).toCryptString().replace("/", "^");
                user.resetPassword = false;
                db.insertUser(user);
                res.redirect("/general/dashboard");
            }
            else {
                req.session.set("last_error", "Passwords did not match.");
            }
        }

        void registerInternalPages() {
            router.get("/static/*", serveStaticFiles("public/", fileSettings))
                  .get("/", &index)
                  .post("/login", &login)
                  .any("*", &verifyLoggedIn)
                  .get("/logout", &logout)
                  .post("/resetpw", &reset_password)
                  .get("/general/:action", &dashboard)
                  .get("/:vm_id/:action", &vm_dashboard)
                  .any("*", &verifyAdmin)
                  .get("/admin/:action", &admin_panel)
//                  .post("/admin/:action", &admin_do)
                  .post("/admin/user/:action", &admin_user_target)
                  .post("/admin/user/:target/:action", &admin_user_target_do)
                  .post("/admin/node/:action", &admin_node_target)
                  .post("/admin/node/:target/:action", &admin_node_target_do)
                  .post("/admin/vps/:action", &admin_vm_target)
                  .post("/admin/vps/:target/:action", &admin_vm_target_do);

            version(Debug) {
                router.get("/debug/:action", &debugGetHandler)
                      .post("/debug/:action", &debugPostHandler);
            } 
        }


    }

    public {
        DatabaseDriver getDB() {
            return db;
        }

        URLRouter getRouter() {
            return router;
        }

        Widget[][string] getWidgets() {
            return widgets;
        }

        void registerSidebar(string category, string displayName, string displayIcon, Sidebar[] entries) {
            sectionEntries[category][displayName] = entries;
            sectionIcons[category][displayName] = displayIcon;
        }

        int registerWidget(Widget w, string templateName = "dashboard.dt") {
            widgets[templateName] ~= w;
            return 1;
        }

        int registerVPSWidget(Widget w) {
            widgets["vps/dashboard.dt"] ~= w;
            return 1;
        }
    }

    this() {
        router = new URLRouter;
        httpSettings = new HTTPServerSettings;
        fileSettings = new HTTPFileServerSettings;
        httpSettings.port = 8080;
        httpSettings.sessionStore = new RedisSessionStore("127.0.0.1", 5, 6379);
        httpSettings.bindAddresses = ["0.0.0.0"];
        fileSettings.serverPathPrefix = "/static";
        registerInternalPages();


        redis_host = "192.168.1.17";
        redis_port = 6379;
        redis_password = "";
        db = new RedisDatabaseDriver("127.0.0.1", 6379);
        listener = listenHTTP(httpSettings, router);
    }

    ~this() {
        listener.stopListening();

    }

}
