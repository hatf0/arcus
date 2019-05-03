module scylla.core.server;
import vibe.d;
import std.stdio;
import bap.core.node;
import bap.model;
import bap.core.redis;
import bap.core.db;
import scylla.models.config;
import vibe.web.auth;
import vibe.http.session;
import vibe.web.web : noRoute;
import scylla.core.kintsugi;
import scylla.core.resource_manager;
import asdf;

class ScyllaServer {
    private {
        ScyllaConfig serverConfig;
        RedisDatabaseDriver db;
        RedisDatabase keyStore;
	ResourceManager rem;
        Kintsugi vmServer;
        string configPath;
    };

    import std.file;

    void createVPSDisk(VPS vps) {
        if(vps.osTemplate == "ubuntu") {
            import std.process, std.format;
            string disk_path = "/srv/scylla/disk_images/" ~ vps.uuid;
            string kernel_path = "/srv/scylla/boot_images/" ~ vps.uuid;
            if(!exists(disk_path)) {
                mkdir(disk_path);
            }

            if(!exists(kernel_path)) {
                mkdir(kernel_path);
            }

            if(exists(disk_path ~ "/" ~ vps.osTemplate)) {
                remove(disk_path ~ "/" ~ vps.osTemplate);
            }

            if(exists(kernel_path ~ "/" ~ vps.osTemplate)) {
                remove(kernel_path ~ "/" ~ vps.osTemplate);
            }

            auto a = executeShell("cp /srv/scylla/disk_images/generic/" ~ vps.osTemplate ~ " " ~ disk_path);
            writeln(a.output);
            auto b = executeShell("cp /srv/scylla/boot_images/generic/" ~ vps.osTemplate ~ " " ~ kernel_path);
            writeln(b.output);

            auto c = executeShell(format!"truncate -s %dG %s"(vps.driveSizes["rootfs"], disk_path ~ "/" ~ vps.osTemplate)); 
            writeln(c.output);

            writeln(executeShell("e2fsck -f -y " ~ disk_path ~ "/" ~ vps.osTemplate).output);
            writeln(executeShell("resize2fs " ~ disk_path ~ "/" ~ vps.osTemplate).output);

            vps.boot.kernelImagePath = kernel_path ~ "/" ~ vps.osTemplate;
            import firecracker_d.models.drive;

            bool foundRootDevice = false;

            foreach(drive; vps.drives) {
                if(drive.isRootDevice) {
                    foundRootDevice = true;
                    drive.pathOnHost = disk_path ~ "/" ~ vps.osTemplate;
                }
            }

            if(!foundRootDevice) {
                Drive _d;
                _d.driveID = "rootfs";
                _d.pathOnHost = disk_path ~ "/" ~ vps.osTemplate;
                _d.isRootDevice = true;
                _d.isReadOnly = false;
                vps.drives ~= _d; 
            }

            db.insertVPS(vps);
        }
        else {
            writeln("unknown template ", vps.osTemplate);
        }

    }


    void loadConfig(string path = "./config.json") {
        import std.file, std.json, jsonizer;
        if(exists(path)) {
            string c = cast(string)read(path);
            JSONValue _c = parseJSON(c);
            serverConfig = fromJSON!ScyllaConfig(_c);
        }
        else {
            serverConfig = ScyllaConfig();
        }
    }

    void saveConfig(string path = "") {
        if(path == "") {
            path = configPath;
        }

        import std.file;
        try {
            write(path, serverConfig.stringify);
        } catch(FileException e) {
            logError("could not save config");
        }
    }
    void startListener() {
        if(serverConfig.onboarded) {
            db = new RedisDatabaseDriver(serverConfig.redisHost, serverConfig.redisPort);
            keyStore = db.getClient().getDatabase(4); 
        }
        else {
            logInfo("server has not been onboarded.. please initialize it.");
        }

    }

    this(string _configPath = "./config.json") {
        configPath = _configPath;
        vmServer = new Kintsugi();
        loadConfig(configPath);
    }
};

