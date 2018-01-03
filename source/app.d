import std.stdio;
import vibe.d;
import requests;
import factorio;
import dauth;
import vibe.data.serialization : name;
import std.conv;

MongoClient client;

enum Permissions {
	PERM_MANAGE_FACTORIO = 0x01,
	PERM_MANAGE_VPN = 0x02,
	PERM_MANAGE_USERS = 0x04,
	PERM_MANAGE_ROLES = 0x08
}

struct User {
	string name;
	string role_name;
	string profile_pic_url;
	string hashed_password;
}

struct Role {
	string name;
	string description;
	int perms;
}

bool isUserPermitted(User us, int id) {
	Nullable!Role role = client.getCollection("web.roles").findOne!Role(["name": us.role_name]);
	if(!role.isNull) {
		Role actualRole = role;
		if(actualRole.perms & id) {
			return true;
		}
	}
	return false;
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
	if(!uu.isNull && uu.hashed_password != "") {
		okay = isSameHash(toPassword(req.form["password"].dup), parseHash(uu.hashed_password));
	}
	if(uu.hashed_password == "") {
		okay = true; //Bypass it all if they don't have a password... anyways..
	}

	//logInfo(req.form["username"]);
	//logInfo(req.form["password"]);
	if(okay) {
		auto session = res.startSession();
		session.set("logged_out", 0);
		User norm = uu;
		session.set("user", norm);
		session.set("last_error", "ERR_SUCCESS");
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
		else {
			res.redirect("/dashboard");
		}
		//res.render!("index.dt", loggedOut);
	}

	res.render!("index.dt", loggedOut);
}

void vpnStatus(HTTPServerRequest req, HTTPServerResponse res) {
	if(req.session) {
		User us = req.session.get!User("user");
		if(!isUserPermitted(us, Permissions.PERM_MANAGE_VPN)) {
			req.session.set("last_error", "ERR_NO_PERMS");
			res.redirect("/dashboard");
		}
 		res.render!("vpn-status.dt", us);
	}
}

void dashboard(HTTPServerRequest req, HTTPServerResponse res) {
	User us = req.session.get!User("user");
	string lastError = req.session.get!string("last_error");
	req.session.set("last_error", "ERR_SUCCESS");
	Nullable!Role role = client.getCollection("web.roles").findOne!Role(["name": us.role_name]);
	Role actualRole;
	if(!role.isNull) {
		actualRole = role;
	}
	res.render!("dashboard.dt", us, actualRole, lastError);
}

void logout(HTTPServerRequest req, HTTPServerResponse res) {
	req.session.set("logged_out", 1);
	res.redirect("/");
}

void verifyLogin(HTTPServerRequest req, HTTPServerResponse res) {
	if(!req.session)
		res.redirect("/");
}

string[] genRoleList() {
	auto roleCol = client.getCollection("web.roles");
	string[] ret;
	foreach(r; roleCol.find!Role()) {
		ret ~= r.name;
	}
	return ret;
}

void role_add(HTTPServerRequest req, HTTPServerResponse res) {
	User us = req.session.get!User("user");
	if(!isUserPermitted(us, Permissions.PERM_MANAGE_ROLES)) {
		req.session.set("last_error", "ERR_NO_PERMS");
		res.redirect("/dashboard");
	}
	string lastError = req.session.get!string("last_error");
	req.session.set("last_error", "ERR_SUCCESS");
	res.render!("role-add.dt", us, lastError);
}

void role_create(HTTPServerRequest req, HTTPServerResponse res) {

	int perms = 0;
	string rolen = "";
	string role_desc = "";
	User us = req.session.get!User("user");
	if(isUserPermitted(us, Permissions.PERM_MANAGE_ROLES)) {
		foreach(i; req.form) {
			if(i[0] == "permsList") {
				switch(i[1]) {
					case "MNG_VPN":
						perms |= Permissions.PERM_MANAGE_VPN;
						break;
					case "MNG_FAC":
						perms |= Permissions.PERM_MANAGE_FACTORIO;
						break;
					case "ADM_USERS":
						perms |= Permissions.PERM_MANAGE_USERS;
						break;
					case "ADM_ROLES":
						perms |= Permissions.PERM_MANAGE_ROLES;
						break;
					default:
						break;
				}
			}
			else if(i[0] == "roleName") {
				rolen = i[1];
			}
			else if(i[0] == "roleDesc") {
				role_desc = i[1];
			}
		}
	}
	else {
		req.session.set("last_error", "ERR_NO_PERMS");
		res.redirect("/dashboard");
	}
	if(rolen == "" || role_desc == "") {
		req.session.set("last_error", "ERR_ROLE_FAIL");
		res.redirect("/admin-add-role");
		return;
	}
	auto roles = client.getCollection("web.roles");
	Role newRole;
	newRole.name = rolen;
	newRole.description = role_desc;
	newRole.perms = perms;
	roles.insert(newRole);
	req.session.set("last_error", "ERR_ROLE_SUCCESS");
	res.redirect("/admin-add-role");
}

void role_remove(HTTPServerRequest req, HTTPServerResponse res) {
	User us = req.session.get!User("user");
	if(isUserPermitted(us, Permissions.PERM_MANAGE_ROLES)) {
		string[] roles = genRoleList();
		string lastError = req.session.get!string("last_error");
		req.session.set("last_error", "ERR_SUCCESS");
		res.render!("role-del.dt", us, roles, lastError);
	}
}

void role_del(HTTPServerRequest req, HTTPServerResponse res) {
	User us = req.session.get!User("user");
	if(isUserPermitted(us, Permissions.PERM_MANAGE_ROLES)) {
		auto roles = client.getCollection("web.roles");
		foreach(i; req.form) {
			if(i[0] == "rolesList") {
				if(i[1] == "Baddest motherfucker" || i[1] == "Unpriviledged")  {
					req.session.set("last_error", "ERR_ROLE_FAIL");
					res.redirect("/admin-del-role");
					return;
				}
				else {
					Nullable!Role role = roles.findOne!Role(["name": i[1]]);
					if(!role.isNull) {
						Role eeee = role;
						roles.remove!Role(eeee);
						req.session.set("last_error", "ERR_ROLE_SUCCESS");
					}
					else {
						req.session.set("last_error", "ERR_ROLE_FAIL");
					}
				}
			}
		}
		res.redirect("/admin-del-role");

	}	
}

void main() {
	auto router = new URLRouter;
	router.get("*", serveStaticFiles("public/"))
		  .get("/", &index)
		  .post("/attemptLogin", &login)
		  .any("*", &verifyLogin)
		  .get("/logout", &logout)
		  .get("/vpn-status", &vpnStatus)
		  .get("/admin-add-role", &role_add)
		  .post("/admin-crt-role", &role_create)
		  .get("/admin-del-role", &role_remove)
		  .post("/admin-rem-role", &role_del)
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
   	Nullable!User unPriv = users.findOne!User(["name": "guest"]);
   	if(unPriv.isNull) {
   		User them;
   		them.name = "guest";
   		them.role_name = "Unpriviledged";
   		them.profile_pic_url = "https://almsaeedstudio.com/themes/AdminLTE/dist/img/user2-160x160.jpg";
   		them.hashed_password = makeHash(toPassword("test".dup)).toString();
   		users.insert(them);
   	}

   	auto roles = client.getCollection("web.roles");
   	Nullable!Role mofo = roles.findOne!Role(["name": "Baddest motherfucker"]);
   	if(mofo.isNull) {
   		Role mf;
   		mf.name = "Baddest motherfucker";
   		mf.description = "Self-explanatory.";
   		mf.perms = Permissions.PERM_MANAGE_ROLES | Permissions.PERM_MANAGE_USERS | Permissions.PERM_MANAGE_VPN | Permissions.PERM_MANAGE_FACTORIO;
   		roles.insert(mf);
   	}
   	Nullable!Role up = roles.findOne!Role(["name": "Unpriviledged"]);
   	if(up.isNull) {
   		Role ok;
   		ok.name = "Unpriviledged";
   		ok.description = "Nerrrd";
   		ok.perms = 0;
   		roles.insert(ok);
   	}



    runApplication();
}