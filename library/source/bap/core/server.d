module bap.core.server;
import bap.core.db;
import bap.model;
import vibe.vibe;

interface ServerREST {
    
    @path("/api/v1/admin/node/:action") nothrow string postAdminNodeAction(string api_key, string data, string _action); 

    @path("/api/v1/admin/node/:target/:action") nothrow string postAdminNodeTarget(string api_key, string data, string _target, string _action);

    @path("/api/v1/admin/user/:action") nothrow string postAdminUserAction(string api_key, string data, string _action);

    @path("/api/v1/admin/user/:target/:action") nothrow string postAdminUserTarget(string api_key, string data, string _target, string _action);

    @path("/api/v1/admin/vps/:action") nothrow string postAdminVPSAction(string api_key, string data, string _action);

    @path("/api/v1/admin/vps/:target/:action") nothrow string postAdminVPSTarget(string api_key, string data, string _target, string _action);

    @path("/api/v1/user/:action") nothrow string postUserAction(string api_key, string data, string _action);

    @path("/api/v1/vps/:target") nothrow string getVPS(string api_key, string _target);

    @path("/api/v1/vps/:target/:category") nothrow string getVPSInfo(string api_key, string data, string _target, string _category);

    @path("/api/v1/vps/:target/:action") nothrow string postVPSAction(string api_key, string data, string _target, string _action);

}

interface Server {
    DatabaseDriver getDB();
    Widget[][string] getWidgets(); 
    URLRouter getRouter();
    void registerSidebar(string category, string displayName, string displayIcon, Sidebar[] entries);
    int registerWidget(Widget w, string templateName = "dashboard.dt");
    int registerVPSWidget(Widget w);
};
