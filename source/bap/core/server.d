module bap.core.server;
import bap.model;
import vibe.d;
import std.concurrency;
import bap.core.db;
import bap.core.redis;

class Server {
    private { 
        HTTPFileServerSettings fileSettings;
        HTTPServerSettings httpSettings;
        HTTPListener listener;

        Sidebar[][string][string] sectionEntries;
        string[string] sectionIcons;

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
                    string[string] _s = sectionIcons.dup;
                    dst.compileHTMLDietFile!("generic/sidebar_entry.dt", entries, _s, category);

                    return to!string(dst.data);
            }
            return "";
        }

        void pageRenderer(HTTPServerRequest req, HTTPServerResponse res, string templateName = "dashboard.dt") {
            User user;
            string lastError;
            if(req.session) {
                user = this.getFromSession(req);
                lastError = req.session.get!string("last_error");
                req.session.set("last_error", "ERR_SUCCESS");
            }

            string sidebarContents = generateSidebars(["Management", "Resources"]);

            switch(templateName) {
              case "dashboard.dt":
                sidebarContents = generateSidebars(["General", "Resources"]);
                res.render!("dashboard.dt", user, lastError, sidebarContents, db, widgets, templateName);
                break;
              case "vps/dashboard.dt":
                res.render!("vps/dashboard.dt", user, lastError, sidebarContents, db, widgets, templateName);
                break;
              case "vps/disks.dt":
                res.render!("vps/disks.dt", user, lastError, sidebarContents, db, widgets, templateName);
                break;
              case "vps/advanced.dt":
                res.render!("vps/advanced.dt", user, lastError, sidebarContents, db, widgets, templateName);
                break;
              case "vps/network.dt":
                res.render!("vps/network.dt", user, lastError, sidebarContents, db, widgets, templateName);
                break;
              case "vps/redeploy.dt":
                res.render!("vps/redeploy.dt", user, lastError, sidebarContents, db, widgets, templateName);
                break;
              case "vps/statistics.dt":
                res.render!("vps/statistics.dt", user, lastError, sidebarContents, db, widgets, templateName);
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

        }

        void registerInternalPages() {
            router.get("/static/*", serveStaticFiles("public/", fileSettings))
                  .get("/", &index)
                  .post("/login", &login)
                  .any("*", &verifyLoggedIn)
                  .get("/logout", &logout)
                  .get("/general/:action", &dashboard)
                  .get("/:vm_id/:action", &vm_dashboard)
                  .get("/ws", handleWebSockets(&webSocketHandler))
                  .any("*", &verifyAdmin)
                  .get("/admin/:action", &admin_panel);

            version(Debug) {
                router.get("/debug/:action", &debugGetHandler)
                      .post("/debug/:action", &debugPostHandler);
            } 
        }


    }

    public {
        Widget[][string] widgets;
        Widget[] dashboardWidgets;
        Widget[] vpsDashboardWidgets;
        URLRouter router;
        DatabaseDriver db;

        void webSocketHandler(scope WebSocket sock) {
            import std.stdio;
            sock.send(`{"event": "hello"}`);

            int status = 0;

            while(sock.connected) {
                import std.json;
                JSONValue j = ["event": "update"]; 
                j["id"] = JSONValue("info-widget-icon");
                j["class"] = JSONValue("info-box-icon bg-" ~ (status ? "red" : "aqua"));

                JSONValue t = ["event": "update"];
                t["id"] = JSONValue("info-widget-text");
                t["text"] = JSONValue((status ? "OFFLINE" : "ONLINE"));

                sock.send(j.toString());
                sock.send(t.toString());
                status ^= 1;
                sleep(10.seconds);
            }

        }

        void registerSidebar(string category, string displayName, string displayIcon, Sidebar[] entries) {
            sectionEntries[category][displayName] = entries;
            sectionIcons[displayName] = displayIcon;
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
        httpSettings.bindAddresses = ["127.0.0.1"];
        fileSettings.serverPathPrefix = "/static";
        registerInternalPages();

        db = new RedisDatabaseDriver("127.0.0.1", 6379);

        listener = listenHTTP(httpSettings, router);
    }

    ~this() {
        listener.stopListening();

    }

}
