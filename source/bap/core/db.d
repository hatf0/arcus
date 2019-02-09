module bap.core.db;
public import bap.models.vps;
public import bap.core.node;
public import bap.models.user;
public import std.typecons;
public import std.uuid;

interface DatabaseDriver {

  bool authenticateUser(string username, string hash);

  bool insertUser(User user);

  bool deleteUser(string username);

  Nullable!User getUser(string username);

  bool insertVPS(VPS vps);

  bool deleteVPS(string machineID);

  Nullable!VPS getVPS(string machineID);

	bool insertNode(Node node);
	
	bool deleteNode(string name);
	
	Nullable!Node getNode(string name);

}


