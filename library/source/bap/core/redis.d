module bap.core.redis;
import bap.model;
import bap.core.db;
import bap.core.node;
import std.json;
import asdf;
import vibe.d;
import std.algorithm.searching : canFind;
import std.string;

class RedisDatabaseDriver : DatabaseDriver
{
    private
    {
        RedisClient redis;
        RedisDatabase users;
        RedisDatabase vpses;
        RedisDatabase nodes;
    }

    bool authenticateUser(string username, string password) nothrow
    in
    {
        assert(username != "", "username cannot be null");
        assert(password != "", "password to compare cannot be null");
    }
    do
    {
        string hash;
        try
        {
            hash = users.request!string("json.get", username, "hash");
        }
        catch (Exception e)
        {
            logError("Caught exception when trying to get user's password hash");
            return false;
        }

        if (hash.length == 0)
        {
            return false;
        }

        hash = hash.replace("\"", "");
        if (hash == "(nil)" || hash == " " || hash == "")
        {
            bool ret = false;
            try
            {
                if (users.request!string("json.get", username, "required_password_reset") == "true")
                {
                    ret = true;
                }
            }
            catch (Exception e)
            {
                logError("Could not check if user was due for a password reset..");
            }
            return ret;
        }
        else
        {
            import dauth;

            try
            {
                Password p = toPassword(password.dup);
                if (isSameHash(p, parseHash(hash.replace("^", "/").strip())))
                {
                    return true;
                }
            }
            catch (Exception e)
            {
                logInfo("user's hash was: '" ~ hash ~ "'");
                logError("Caught a hashing error while attempting to authenticate");
            }
        }
        return false;
    }

    bool insertUser(User user) nothrow
    in
    {
        assert(user.username != "", "username cannot be null");
        assert(user.stringify != "{}", "user must be serializable to json");
    }
    do
    {
        string userJSON;
        try
        {
            userJSON = user.stringify;
        }
        catch (Exception e)
        {
            // THIS SHOULD NEVER HAPPEN
            logError("failed to serialize user to json");
            return false;
        }

        string redisOutput;

        try
        {
            redisOutput = users.request!string("json.set", user.username, ".", userJSON);
        }
        catch (Exception e)
        {
            logError("failed to set user with redis");
        }
        if (redisOutput.canFind("error"))
        {
            return false;
        }
        return true;
    }

    bool deleteUser(string username) nothrow
    in
    {
        assert(username != "", "username cannot be null");
    }
    do
    {
        try
        {
            users.request!string("json.del", username);
        }
        catch (Exception e)
        {
            logError("got an error while attempting to delete");
            return false;
        }
        return true;
    }

    Nullable!User getUser(string username) nothrow
    in
    {
        assert(username != "", "username cannot be null");
    }
    do
    {
        Nullable!User ret = Nullable!User.init;
        string user_json;
        try
        {
            user_json = users.request!string("json.get", username);
        }
        catch (Exception e)
        {
            logError("got an error while attempting to get user");
            return ret;
        }

        if (user_json.length != 0)
        {
            if (user_json != "(nil)" && user_json[0] == '{')
            {
                try
                {
                    User u = user_json.deserialize!User();
                    ret = u;
                }
                catch (DeserializationException e)
                {
                    logError("got an error while attempting to deserialize user");
                }
                catch (Exception e)
                {
                    logError("caught generic exception while attempting to deserialize user");
                }
            }
        }
        return ret;
    }

    User[] getAllUsers() nothrow
    {
        User[] collected;
        import std.format, core.exception;

        try
        {
            RedisReply!string userList = users.keys!string("*");
            while (userList.hasNext())
            {
                string username = userList.next!string();
                Nullable!User user = getUser(username);
                if (!user.isNull)
                {
                    collected ~= user;
                }
            }
        }
        catch (Exception e)
        {
            logError("Caught exception while getting all users");
        }

        return collected;
    }

    bool insertVPS(VPS vps) nothrow
    in
    {
        assert(vps.uuid != "", "vps uuid cannot be null");
        assert(vps.stringify != "", "vps has to be serializable");
    }
    do
    {
        string redisOutput;
        try
        {
            redisOutput = vpses.request!string("json.set", vps.uuid, ".", vps.stringify);
        }
        catch (Exception e)
        {
            logError("got exception while attempting to set object");
            return false;
        }

        if (redisOutput.canFind("error"))
        {
            return false;
        }
        return true;
    }

    bool deleteVPS(string machineID) nothrow
    in
    {
        assert(machineID != "", "machine id cannot be null");
    }
    do
    {
        try
        {
            vpses.request!string("json.del", machineID);
        }
        catch (Exception e)
        {
            logError("could not delete vps");
            return false;
        }
        return true;
    }

    Nullable!VPS getVPS(string machineID) nothrow
    in
    {
        assert(machineID != "", "machine id cannot be null");
    }
    do
    {
        Nullable!VPS ret = Nullable!VPS.init;
        string vps_json;
        try
        {
            vps_json = vpses.request!string("json.get", machineID);
        }
        catch (Exception e)
        {
            logError("got an error while attempting to get VPS");
            return ret;
        }

        if (vps_json.length != 0)
        {
            if (vps_json[0] == '{')
            {
                import std.stdio : writeln;

                try
                {
                    VPS v = vps_json.deserialize!VPS();
                    ret = v;
                }
                catch (DeserializationException e)
                {
                    logError("got an error while attempting to deserialize VPS");
                }
                catch (Exception e)
                {
                    logError("caught generic exception while attempting to deserialize vps");
                }
            }
        }
        return ret;
    }

    VPS[] getAllVPS() nothrow
    {
        VPS[] collected;
        import std.format;

        try
        {
            RedisReply!string vpsList = vpses.keys!string("*");
            while (vpsList.hasNext())
            {
                string uuid = vpsList.next!string();
                Nullable!VPS vps = getVPS(uuid);
                if (!vps.isNull)
                {
                    collected ~= vps;
                }
            }
        }
        catch (Exception e)
        {
            logError("could not collect vps list");
        }

        return collected;
    }

    bool insertNode(Node node) nothrow
    in
    {
        assert(node.name != "", "node name must not be null");
        assert(node.stringify != "", "node must be serializable to json");
    }
    do
    {
        string redisReply;
        try
        {
            redisReply = nodes.request!string("json.set", node.name, ".", node.stringify);
        }
        catch (Exception e)
        {
            logError("could not set node");
            return false;
        }

        if (redisReply.canFind("error"))
        {
            return false;
        }
        return true;
    }

    bool deleteNode(string name) nothrow
    in
    {
        assert(name != "", "node name cannot be null");
    }
    do
    {
        try
        {
            nodes.request!string("json.del", name);
        }
        catch (Exception e)
        {
            logError("could not delete node");
            return false;
        }
        return true;
    }

    Nullable!Node getNode(string name) nothrow
    in
    {
        assert(name != "", "name must not be null");
    }
    do
    {
        Nullable!Node node = Nullable!Node.init;
        string node_json;
        try
        {
            node_json = nodes.request!string("json.get", name);
        }
        catch (Exception e)
        {
            logError("could not get node");
        }
        if (node_json.length != 0)
        {
            if (node_json != "(nil)" && node_json[0] == '{')
            {
                try
                {
                    Node nn = node_json.deserialize!Node;
                    node = nn;
                }
                catch (DeserializationException e)
                {
                    logError("got error while attempting to deserialize node");
                }
                catch (Exception e)
                {
                    logError("got generic exception while attempting to deserialize node");
                }
            }
        }
        return node;
    }

    Node[] getAllNode() nothrow
    {
        Node[] collected;
        import std.format;

        try
        {
            RedisReply!string nodeList = nodes.keys!string("*");
            while (nodeList.hasNext())
            {
                string hostname = nodeList.next!string();
                Nullable!Node node = getNode(hostname);
                if (!node.isNull)
                {
                    collected ~= node;
                }
            }
        }
        catch (Exception e)
        {
            logError("could not get node list");
        }

        return collected;
    }

    RedisClient getClient()
    {
        return redis;
    }

    this(string ip, ushort port)
    {
        redis = new RedisClient(ip, port);
        users = redis.getDatabase(0);
        vpses = redis.getDatabase(1);
        nodes = redis.getDatabase(2);
    }

};
