module bap.models.user;
import bap.models.role;
import bap.models.vps;
import bap.core.server;
import jsonizer;

struct User {
  mixin JsonizeMe;
  @jsonize("name") string username;
  @jsonize("hash") string hashedPassword;

  @jsonize("full_name") string name;
  @jsonize("picture") string profilePicURL;

  @jsonize("company") string company;

  @jsonize("admin") bool admin;

	// list contains UUIDs
  @jsonize("vps_list") string[] servers;

	string stringify() {
        JSONValue j = jsonizer.toJSON(this);
        return j.toString;
	}

}

import vibe.d;
import bap.core.db;
import std.json;

User getFromSession(Server s, HTTPServerRequest req) {
		User r;
		if(req.session) {
				string username = req.session.get!string("user");
				import core.exception;
				try {
					Nullable!User u = s.db.getUser(username);
					if(!u.isNull) {	
						r = u;
					}
					else {
						logInfo("Got a null user? wtf?");
					}
				}
				catch(JsonizeException) {
					logInfo("Was not able to get a valid session for user..");
					return r;
				}
				catch(AssertError) {
					logInfo("Assertion error. Probably happened during deserialization.");
					return r;
				}
		}
		return r;
}




