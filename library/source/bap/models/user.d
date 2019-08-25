module bap.models.user;
import bap.models.role;
import bap.models.vps;
import bap.core.server;
import asdf;

struct User
{
    @serializationKeys("name") string username;
    @serializationKeys("hash") string hashedPassword;

    @serializationKeys("full_name") string name;
    @serializationKeys("picture") string profilePicURL;
    @serializationKeys("email") string email;
    @serializationKeys("admin") bool admin;
    @serializationKeys("timestamp") string lastLoggedIn;
    @serializationKeys("required_password_reset") bool resetPassword;

    // list contains UUIDs
    @serializationKeys("vps_list") string[] servers;

    @serializationKeys("api_key") string apiKey;

    string stringify()
    {
        with (asdf)
        {
            return this.serializeToJson();
        }
    }

}

import vibe.d;
import bap.core.db;
import std.json;

User getFromSession(Server s, HTTPServerRequest req)
{
    User r = User.init;
    if (req.session)
    {
        string username = req.session.get!string("user");
        import core.exception;

        try
        {
            Nullable!User u = s.getDB().getUser(username);
            if (!u.isNull)
            {
                r = u;
            }
            else
            {
                logInfo("Got a null user? wtf?");
            }
        }
        catch (DeserializationException)
        {
            logInfo("Was not able to get a valid session for user..");
            return r;
        }
        catch (AssertError)
        {
            logInfo("Assertion error. Probably happened during deserialization.");
            return r;
        }
    }
    return r;
}
