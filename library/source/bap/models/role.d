module bap.models.role;
import asdf; 

struct Role {
    string name;
    string[] permissions;

    bool removePermission(string permission) {
        if(hasPermission(permission)) {
            import std.algorithm.mutation;
            permissions = permissions.remove(permission);
            return true;
        }
        return false;
    }

    bool hasPermission(string permission) {
        import std.algorithm.searching;
        return permissions.canFind(permission);
    }
}


