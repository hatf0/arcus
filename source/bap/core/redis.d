module bap.core.redis;
import bap.model;
import bap.core.db;
import bap.core.node;
import std.json;
import jsonizer;
import vibe.d;

class RedisDatabaseDriver : DatabaseDriver {
  private {
    RedisClient redis;
    RedisDatabase users;
    RedisDatabase vpses;
    RedisDatabase nodes;
  }

  bool authenticateUser(string username, string password) {
    string ret = users.request!string("json.get", username, "hash"); 
    if(ret == "(nil)" || ret == " " || ret == "") {
      return false;
    }
    else {
      ret = ret.replace("\"", "");
      import dauth;
      import std.string;
      Password p = toPassword(password.dup);
      if(isSameHash(p, parseHash(ret.replace("^", "/").strip()))) {
        return true;
      }
    }
    return false;
  }

  bool insertUser(User user) {
    string ret = users.request!string("json.set", user.username, ".", user.stringify); 
    import std.string;
    if(ret.canFind("error")) {
      return false;
    }
    return true;
  }

  bool deleteUser(string username) {
    users.request!string("json.del", username);
    return true;
  }
  
  Nullable!User getUser(string username) {
    Nullable!User ret = Nullable!User.init;
    string user_json = users.request!string("json.get", username);
    if(user_json != "(nil)") {
      JSONValue j = parseJSON(user_json);
      User u = fromJSON!User(j);
      ret = u;
    }
    return ret;
  }

  bool insertVPS(VPS vps) {
    string ret = vpses.request!string("json.set", vps.uuid, ".", vps.stringify); 
    import std.string;
    if(ret.canFind("error")) {
      return false;
    }
    return true;
  }

  bool deleteVPS(string machineID) {
    vpses.request!string("json.del", machineID);
    return true;
  }

  Nullable!VPS getVPS(string machineID) {
    Nullable!VPS ret = Nullable!VPS.init;
    string vps_json = vpses.request!string("json.get", machineID);
    if(vps_json != "(nil)") {
      JSONValue n = parseJSON(vps_json);
      VPS v = fromJSON!VPS(n);
      ret = v;
    } 
    return ret;
  }

  bool insertNode(Node node) {
    string ret = nodes.request!string("json.set", node.name, ".", node.stringify); 
    import std.string;
    if(ret.canFind("error")) {
      return false;
    }
    return true;
  }

  bool deleteNode(string name) {
    nodes.request!string("json.del", name);
    return true;
  }

  Nullable!Node getNode(string name) {
    Nullable!Node node = Nullable!Node.init;
    string node_json = nodes.request!string("json.get", name);
    if(node_json != "(nil)") {
      JSONValue n = parseJSON(node_json);
      Node nn = fromJSON!Node(n);
      node = nn;
    }
    return node;
  }

  this(string ip, ushort port) {
    redis = new RedisClient(ip, port);
    users = redis.getDatabase(0);
    vpses = redis.getDatabase(1);
    nodes = redis.getDatabase(2);
  }
    
};
