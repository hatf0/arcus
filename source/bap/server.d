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

        void pageRenderer(HTTPServerRequest req, HTTPServerResponse res, string templateName = "dashboard.dt") {
            User user;
            string lastError;
            string authKey;
            VPS vps;
            if(req.session) {
                user = this.getFromSession(req);
                lastError = req.session.get!string("last_error");
                req.session.set("last_error", "ERR_SUCCESS");
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
              else {
                sidebarContents = generateSidebars(["Management", "Resources"]);
              }
            }
            else {
              sidebarContents = generateSidebars(["Management", "Resources"]);
            }

            Server serverInterface = this;
            switch(templateName) {
              case "dashboard.dt":
                string[] sidebars = ["General", "Resources"];
                sidebarContents = generateSidebars(sidebars);
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

        void admin_target_do(HTTPServerRequest req, HTTPServerResponse res) {
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
              else {
                logInfo("got action: " ~ req.params["action"]);
              }
            }
            else {
              logInfo("got a null node");
            }
        }

        void vm_do(HTTPServerRequest req, HTTPServerResponse res) {
            if(req.params["vm_id"] == "admin") return;
            if(req.params["vm_id"] == "debug") return;
            User user;
            user = this.getFromSession(req);

            import std.algorithm.searching;
            if(!user.servers.canFind(req.params["vm_id"])) {
              req.session.set("last_error", "ERR_NO_PERMS");
              res.redirect("/");
              return;
            }



        }

        void registerInternalPages() {
            router.get("/static/*", serveStaticFiles("public/", fileSettings))
                  .get("/", &index)
                  .post("/login", &login)
                  .any("*", &verifyLoggedIn)
                  .get("/logout", &logout)
                  .get("/general/:action", &dashboard)
                  .get("/:vm_id/:action", &vm_dashboard)
                  .post("/:vm_id/:action", &vm_do)
                  .any("*", &verifyAdmin)
                  .get("/admin/:action", &admin_panel)
//                  .post("/admin/:action", &admin_do)
                  .post("/admin/node/:target/:action", &admin_target_do);

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


        redis_host = "127.0.0.1";
        redis_port = 6379;
        redis_password = "";
        db = new RedisDatabaseDriver("127.0.0.1", 6379);
        listener = listenHTTP(httpSettings, router);
    }

    ~this() {
        listener.stopListening();

    }

}
