module zephyr.models.vps_target;
import zephyr.models.base;
import firecracker_d.models.drive;

//node=local&hostname=test&vcpu_count=2&ram_size=1&disk_size=15&disk_template=ubuntu&user=hatf0"
struct VPSTarget {
    mixin BaseModel;

    @serializationKeys("node_name") string node;

    @serializationKeys("hostname") string hostname;
    
    @serializationKeys("vcpu_count") ulong cpuCount;

    @serializationKeys("ram_size") ulong ramSize;

    @serializationKeys("drives") Drive[] drives;

    @serializationKeys("drive_sizes") ulong[string] driveSizes;

    @serializationKeys("disk_template") string diskTemplate;

    @serializationKeys("target_user") string targetUser;
}


