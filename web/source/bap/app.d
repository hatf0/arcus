module bap.app;
import vibe.d;
import std.stdio;
import bap.model;
import bap.core.server;
import bap.server;

void main()
{
    Server s = new BAPServer();

    Sidebar[] entries;
    entries ~= Sidebar("mdi mdi-view-dashboard", "./dashboard", "Dashboard");
    s.registerSidebar("General", "Overview", "fa-television", entries);

    Sidebar[] vpsManagement;
    vpsManagement ~= Sidebar("mdi mdi-view-dashboard", "./dashboard", "Dashboard");
    vpsManagement ~= Sidebar("mdi mdi-harddisk", "./disks", "Disks");
    vpsManagement ~= Sidebar("mdi mdi-server-network", "./network", "Network");
    vpsManagement ~= Sidebar("mdi mdi-refresh", "./redeploy", "Redeploy");
    vpsManagement ~= Sidebar("mdi mdi-settings", "./advanced", "Advanced");
    s.registerSidebar("Management", "VPS", "fa-server", vpsManagement);

    Sidebar[] support;
    support ~= Sidebar("mdi mdi-account-question", "/", "Live Chat");
    support ~= Sidebar("mdi mdi-help-circle", "/", "Knowledgebase");
    s.registerSidebar("Resources", "Support", "mdi mdi-lifebuoy", support);

    s.registerVPSWidget(Widget("info", 6, 6, 6, 6, Widget.colors.white,
            Widget.colors.none, `
                <script src="/static/ws_alt.js"></script>
                <div class="box-header with-border">
                    <h3 class="box-title">Kernel Log</h3>
                </div>
                <div class="box-body">
                    <div class="direct-chat-messages" id="messages">
                    </div>
                </div>`, "", ""));

    s.registerVPSWidget(Widget("info", 3, 3, 3, 3, Widget.colors.white,
            Widget.colors.yellow, `
                <span class="info-box-text">Status</span>
                <span class="info-box-number" id="info-widget-text">UNKNOWN</span>`,
            "fa fa-power-off", "info-widget"));
    s.registerVPSWidget(Widget("info", 3, 3, 3, 3, Widget.colors.white,
            Widget.colors.aqua, `
                <span class="info-box-text">IP Address</span>
                <span class="info-box-number" id="ip-address">172.16.1.1</span>`,
            "mdi mdi-server-network", "info-widget-2"));

    s.registerVPSWidget(Widget("info", 6, 6, 6, 6, Widget.colors.white,
            Widget.colors.aqua, `
          <div class="box box-primary">     
            <div class="box-header with-border">
              <h3>Quick Actions</h3>
            </div>
            <div class="box-body">
              <div class="btn-group">
                <button style="width: 255px; height: 95px;" class="btn btn-app bg-green" id="vm-start" data-toggle="tooltip" data-placement="top" title="Start">
                  <i class="fa fa-play" style="font-size: 35px;"></i>
                </button>
                <button style="width: 255px; height: 95px;" class="btn btn-app bg-yellow" id="vm-restart" data-toggle="tooltip" data-placement="top" title="Reboot">
                  <i class="fa fa-refresh" style="font-size: 35px;"></i>
                </button>
                <button style="width: 255px; height: 95px;" class="btn btn-app bg-red" id="vm-shutdown" data-toggle="tooltip" data-placement="top" title="Shutdown">
                  <i class="fa fa-power-off" style="font-size: 35px;"></i>
                </button>
              </div>
            </div>
          </div>
                
   `, "", "quick-actions"));

    s.registerVPSWidget(Widget("info", 6, 6, 6, 6, Widget.colors.white,
            Widget.colors.none, `
                <div class="box-header with-border">
                    <h3 class="box-title">CPU Usage</h3>
                </div>
                <div class="box-body">
                    <div class="chart">
                        <canvas id="cpuUsage" style="height: 250px; width: 792px;" width="1584" height="500">
                        </canvas>
                    </div>
                </div>`, "", ""));

    s.registerVPSWidget(Widget("info", 6, 6, 6, 6, Widget.colors.white,
            Widget.colors.none, `
                <div class="box-header with-border">
                    <h3 class="box-title">Network Throughput</h3>
                </div>
                <div class="box-body">
                    <div class="chart">
                        <canvas id="networkIo" style="height: 250px; width: 792px;" width="1584" height="500">
                        </canvas>
                    </div>
                    <script src="/static/vm-graphing.js"></script>
                </div>`, "", ""));
    Sidebar[] adminVMs;
    adminVMs ~= Sidebar("mdi mdi-server", "/admin/vms", "Overview");
    s.registerSidebar("Admin", "VPS", "fa-server", adminVMs);

    Sidebar[] adminNodes;
    adminNodes ~= Sidebar("mdi mdi-server", "/admin/nodes", "Overview");
    s.registerSidebar("Admin", "Node", "fa-server", adminNodes);

    Sidebar[] adminUsers;
    adminUsers ~= Sidebar("mdi mdi-account-settings", "/admin/users", "Overview");
    s.registerSidebar("Admin", "User", "fa-users", adminUsers);

    Sidebar[] adminConfig;
    adminConfig ~= Sidebar("mdi mdi-database", "/admin/config/redis", "Redis");
    adminConfig ~= Sidebar("mdi mdi-database", "/admin/config/influxdb", "InfluxDB");
    adminConfig ~= Sidebar("mdi mdi-chart-line", "/admin/config/grafana", "Grafana");
    adminConfig ~= Sidebar("mdi mdi-server", "/admin/config/orchestrator", "Orchestrator");
    adminConfig ~= Sidebar("mdi mdi-monitor", "/admin/config/bap", "Panel");

    s.registerSidebar("Admin", "Settings", "fa-cogs", adminConfig);

    runApplication();
}
