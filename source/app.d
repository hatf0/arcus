import std.stdio;
import vibe.d;
import requests;
import factorio;
import dauth;
import std.conv;

MongoClient client;

struct User {
	string name;
	string role_name;
	string profile_pic_url;
	string hashed_password;
}

void login(HTTPServerRequest req, HTTPServerResponse res) {
	if(req.session) {
		res.redirect("/dashboard");
		return;
	}

	enforceHTTP("username" in req.form && "password" in req.form, 
		HTTPStatus.badRequest, "Missing username/password..");

	bool okay = false;
	auto u = client.getCollection("web.users");
	Nullable!User uu = u.findOne!User(["name": req.form["username"]]);
	if(!uu.isNull) {
		okay = isSameHash(toPassword(req.form["password"].dup), parseHash(uu.hashed_password));
	}

	//logInfo(req.form["username"]);
	//logInfo(req.form["password"]);
	if(okay) {
		auto session = res.startSession();
		session.set("logged_out", 0);
		User norm = uu;
		session.set("user", norm);
		res.redirect("/dashboard");
	}
	else {
		int loggedOut = 3;
		res.render!("index.dt", loggedOut);
	}
}

void index(HTTPServerRequest req, HTTPServerResponse res) {
	int loggedOut = 0;
	if(req.session) {
		loggedOut = req.session.get!int("logged_out");
		if(loggedOut) {
			res.terminateSession();
		}
		logInfo("%d", loggedOut);
		res.render!("index.dt", loggedOut);
		return;
	}

	if(req.session) 
		res.redirect("/dashboard");
	else {
		res.render!("index.dt", loggedOut);
	}
}

void vpnStatus(HTTPServerRequest req, HTTPServerResponse res) {
	if(req.session) {
		User us = req.session.get!User("user");
		res.render!("vpn-status.dt", us);
	}
}

void dashboard(HTTPServerRequest req, HTTPServerResponse res) {
	User us = req.session.get!User("user");
	res.render!("dashboard.dt", us);
}

void logout(HTTPServerRequest req, HTTPServerResponse res) {
	req.session.set("logged_out", 1);
	res.redirect("/");
}

void verifyLogin(HTTPServerRequest req, HTTPServerResponse res) {
	if(!req.session)
		res.redirect("/");
}

void main() {
	auto router = new URLRouter;
	router.get("*", serveStaticFiles("public/"))
		  .get("/", &index)
		  .post("/attemptLogin", &login)
		  .any("*", &verifyLogin)
		  .get("/logout", &logout)
		  .get("/vpn-status", &vpnStatus)
		  .get("/dashboard", &dashboard);
    
 	client = connectMongoDB("mongodb://127.0.0.1/web");
    auto settings = new HTTPServerSettings;
    settings.port = 6969;
    settings.sessionStore = new MemorySessionStore;
    settings.bindAddresses = ["0.0.0.0"];
    listenHTTP(settings, router);

   	//string pw = makeHash(toPassword("hello world".dup)).toString();
   	//collection.add(User("hatf0", "Baddest mofo", "https://almsaeedstudio.com/themes/AdminLTE/dist/img/user2-160x160.jpg", pw));
   	auto users = client.getCollection("web.users");
   	Nullable!User hatf0 = users.findOne!User(["name": "hatf0"]);
   	if(hatf0.isNull) {
   		User me;
   		me.name = "hatf0";
   		me.role_name = "Baddest motherfucker";
   		me.profile_pic_url = "https://almsaeedstudio.com/themes/AdminLTE/dist/img/user2-160x160.jpg";
   		me.hashed_password = makeHash(toPassword("hello world".dup)).toString();
   		users.insert(me);
   	}


    runApplication();
}