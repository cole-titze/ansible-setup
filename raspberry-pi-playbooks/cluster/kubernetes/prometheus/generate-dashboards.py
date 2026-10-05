"""Generates the Grafana dashboards in dashboards/ (deployed by prometheus.yml). Run: python3 generate-dashboards.py"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dashboards")
DS = {"type": "prometheus", "uid": "${datasource}"}

_id = 0


def nid():
    global _id
    _id += 1
    return _id


def tgt(expr, legend="", ref="A", instant=False, fmt=None):
    t = {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": ref}
    if instant:
        t["instant"] = True
        t["range"] = False
    if fmt:
        t["format"] = fmt
    return t


def thresholds(*steps):
    """steps: (value, color) with first value None."""
    return {"mode": "absolute", "steps": [{"value": v, "color": c} for v, c in steps]}


def stat(title, targets, x, y, w=4, h=4, unit="none", th=None, decimals=None,
         desc="", mappings=None, color_mode="value", text_mode="auto", graph=True):
    defaults = {"unit": unit, "thresholds": th or thresholds((None, "green"))}
    if decimals is not None:
        defaults["decimals"] = decimals
    if mappings:
        defaults["mappings"] = mappings
    return {
        "id": nid(), "type": "stat", "title": title, "description": desc,
        "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": targets,
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "colorMode": color_mode, "graphMode": "area" if graph else "none",
            "textMode": text_mode, "justifyMode": "auto", "orientation": "auto",
        },
    }


def ts(title, targets, x, y, w=12, h=8, unit="none", desc="", stack=False,
       fill=10, minv=None, maxv=None, th=None, th_style="off", legend_calcs=None):
    custom = {
        "drawStyle": "line", "lineWidth": 2, "fillOpacity": fill, "showPoints": "never",
        "spanNulls": True, "stacking": {"mode": "normal" if stack else "none", "group": "A"},
        "thresholdsStyle": {"mode": th_style},
    }
    defaults = {"unit": unit, "custom": custom,
                "thresholds": th or thresholds((None, "green"))}
    if minv is not None:
        defaults["min"] = minv
    if maxv is not None:
        defaults["max"] = maxv
    return {
        "id": nid(), "type": "timeseries", "title": title, "description": desc,
        "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": targets,
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {
            "legend": {"displayMode": "table" if legend_calcs else "list",
                       "placement": "bottom", "calcs": legend_calcs or []},
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
    }


def bargauge(title, targets, x, y, w=12, h=8, unit="none", desc="", th=None, decimals=None):
    defaults = {"unit": unit, "thresholds": th or thresholds((None, "blue")),
                "color": {"mode": "thresholds"}}
    if decimals is not None:
        defaults["decimals"] = decimals
    return {
        "id": nid(), "type": "bargauge", "title": title, "description": desc,
        "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": targets,
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "orientation": "horizontal", "displayMode": "gradient",
            "showUnfilled": True, "valueMode": "color", "namePlacement": "left",
        },
    }


def row(title, y, collapsed=False):
    return {"id": nid(), "type": "row", "title": title, "collapsed": collapsed,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}


def dashboard(uid, title, tags, panels, desc, refresh="1m", time_from="now-24h", links=None):
    return {
        "uid": uid, "title": title, "tags": tags, "description": desc,
        "editable": True, "graphTooltip": 1, "refresh": refresh,
        "schemaVersion": 39, "version": 1, "timezone": "browser",
        "time": {"from": time_from, "to": "now"},
        "links": links or [],
        "templating": {"list": [{
            "name": "datasource", "label": "Data source", "type": "datasource",
            "query": "prometheus", "current": {"text": "Prometheus", "value": "prometheus"},
            "hide": 2,
        }]},
        "annotations": {"list": []},
        "panels": panels,
    }


# ---------------------------------------------------------------- NHL stack health
API = 'namespace="nhl-odds", container="webapi"'
# MCP is long-lived streaming and unmatched routes (endpoint="") are 404 probes; both skew latency
API_ROUTES = API + ', endpoint!~"mcp.*|"'
CF = 'namespace="nhl-odds", container="cloudflared"'
LAN = 'router=~".*nhl-odds.*"'
DBSEL = 'namespace="nhl-odds", pod=~"nhl-odds-database-.*"'

LAT_TH = thresholds((None, "green"), (0.3, "yellow"), (1, "red"))
nhl = []
y = 0
nhl.append(row("Traffic & response time", y)); y += 1
# Traffic is light (a handful of requests an hour), so stats cover the whole dashboard range and
# graphs use 1h windows; 5m windows would mostly be empty and render as gaps.
Q = "histogram_quantile({q}, sum by (le{by}) (rate(http_request_duration_seconds_bucket{{%s}}[{w}])))" % API_ROUTES
nhl += [
    stat("Public requests", [tgt(f"sum(increase(cloudflared_tunnel_total_requests{{{CF}}}[$__range]))", instant=True)],
         0, y, decimals=0, graph=False,
         desc="All real-user traffic in the selected range, counted at the Cloudflare tunnel (pages, assets, API)."),
    stat("API requests", [tgt(f"sum(increase(http_request_duration_seconds_count{{{API}}}[$__range]))", instant=True)],
         4, y, decimals=0, graph=False, desc="Requests handled by the webapi in the selected range."),
    stat("API p50 response", [tgt(Q.format(q=0.5, by="", w="$__range"), instant=True)],
         8, y, unit="s", th=LAT_TH, graph=False, desc="Median API response time over the selected range (MCP excluded)."),
    stat("API p95 response", [tgt(Q.format(q=0.95, by="", w="$__range"), instant=True)],
         12, y, unit="s", th=LAT_TH, graph=False, desc="95th percentile API response time over the selected range (MCP excluded)."),
    stat("API errors (5xx)", [tgt(
        f'sum(increase(http_request_duration_seconds_count{{{API}, code=~"5.."}}[$__range])) '
        f"/ clamp_min(sum(increase(http_request_duration_seconds_count{{{API}}}[$__range])), 1e-9)", instant=True)],
         16, y, unit="percentunit", decimals=1, graph=False,
         th=thresholds((None, "green"), (0.01, "yellow"), (0.05, "red"))),
    stat("Tunnel errors (5xx)", [tgt(
        f'sum(increase(cloudflared_tunnel_response_by_code{{{CF}, status_code=~"5.."}}[$__range])) '
        f"/ clamp_min(sum(increase(cloudflared_tunnel_total_requests{{{CF}}}[$__range])), 1e-9)", instant=True)],
         20, y, unit="percentunit", decimals=1, graph=False,
         th=thresholds((None, "green"), (0.01, "yellow"), (0.05, "red")),
         desc="5xx responses seen by real users in the selected range, including nginx/frontend failures."),
]
y += 4
nhl += [
    ts("Requests per hour", [
        tgt(f"sum(increase(cloudflared_tunnel_total_requests{{{CF}}}[1h]))", "Public (tunnel)", "A"),
        tgt(f"sum(increase(http_request_duration_seconds_count{{{API}}}[1h]))", "API (webapi)", "B"),
        tgt(f"sum(increase(traefik_router_requests_total{{{LAN}}}[1h]))", "LAN (Traefik)", "C"),
    ], 0, y, unit="none", desc="Rolling 1-hour request counts.", legend_calcs=["mean", "max"]),
    ts("API response time (1h windows)", [
        tgt(Q.format(q=0.5, by="", w="1h"), "p50", "A"),
        tgt(Q.format(q=0.95, by="", w="1h"), "p95", "B"),
        tgt(Q.format(q=0.99, by="", w="1h"), "p99", "C"),
    ], 12, y, unit="s", minv=0, th=LAT_TH, th_style="dashed", legend_calcs=["mean", "max"]),
]
y += 8
nhl += [
    ts("p95 response time by endpoint (1h windows)", [tgt(Q.format(q=0.95, by=", endpoint", w="1h"), "{{endpoint}}")],
       0, y, unit="s", minv=0, fill=0, legend_calcs=["mean", "max"],
       desc="Which API routes are slow. Gaps mean the route had no traffic in that hour."),
    ts("Requests per hour by endpoint", [tgt(
        f"sum by (endpoint) (increase(http_request_duration_seconds_count{{{API}}}[1h]))", "{{endpoint}}")],
       12, y, unit="none", stack=True, fill=30, legend_calcs=["mean", "max"]),
]
y += 8
nhl += [
    bargauge("Where API time goes (total seconds, dashboard range)", [tgt(
        f"sort_desc(sum by (endpoint) (increase(http_request_duration_seconds_sum{{{API_ROUTES}}}[$__range])))",
        "{{endpoint}}", instant=True)], 0, y, h=9, unit="s", decimals=1,
        desc="Calls x average duration. The top bar is the endpoint where optimizing saves the most server time."),
    bargauge("Average response by endpoint (dashboard range)", [tgt(
        f"sort_desc(sum by (endpoint) (increase(http_request_duration_seconds_sum{{{API_ROUTES}}}[$__range])) "
        f"/ sum by (endpoint) (increase(http_request_duration_seconds_count{{{API_ROUTES}}}[$__range])))",
        "{{endpoint}}", instant=True)], 12, y, h=9, unit="s", th=LAT_TH,
        desc="Mean response time per route over the selected range."),
]
y += 9
nhl += [
    ts("Responses by status (public)", [tgt(
        f"sum by (status_code) (increase(cloudflared_tunnel_response_by_code{{{CF}}}[1h]))", "{{status_code}}")],
       0, y, unit="none", stack=True, fill=30, desc="Rolling 1-hour response counts at the tunnel, by HTTP status."),
    ts("LAN response time (Traefik, 1h windows)", [
        tgt(f"histogram_quantile(0.5, sum by (le) (rate(traefik_router_request_duration_seconds_bucket{{{LAN}}}[1h])))", "p50", "A"),
        tgt(f"histogram_quantile(0.95, sum by (le) (rate(traefik_router_request_duration_seconds_bucket{{{LAN}}}[1h])))", "p95", "B"),
    ], 12, y, unit="s", minv=0,
       desc="Only nhl-odds.kubecluster (LAN) traffic passes through Traefik; public traffic does not."),
]
y += 8

nhl.append(row("Workloads", y)); y += 1
nhl += [
    bargauge("Replicas available", [tgt(
        'kube_deployment_status_replicas_available{namespace="nhl-odds"} '
        '/ kube_deployment_spec_replicas{namespace="nhl-odds"}', "{{deployment}}", instant=True)],
        0, y, w=8, h=7, unit="percentunit",
        th=thresholds((None, "red"), (0.5, "yellow"), (1, "green"))),
    bargauge("Restarts (24h)", [tgt(
        'sort_desc(sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace="nhl-odds"}[24h])) > 0)',
        "{{pod}}", instant=True)], 8, y, w=8, h=7, decimals=0,
        th=thresholds((None, "green"), (1, "yellow"), (3, "red")),
        desc="Pods that restarted in the last 24h (empty = none)."),
    bargauge("Webapi memory vs limit", [tgt(
        'sum by (pod) (container_memory_working_set_bytes{namespace="nhl-odds", container="webapi"}) '
        '/ sum by (pod) (kube_pod_container_resource_limits{namespace="nhl-odds", container="webapi", resource="memory"})',
        "{{pod}}", instant=True)], 16, y, w=8, h=7, unit="percentunit",
        th=thresholds((None, "green"), (0.75, "yellow"), (0.9, "red"))),
]
y += 7
nhl += [
    ts("CPU by pod", [tgt(
        'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="nhl-odds", container!=""}[5m]))',
        "{{pod}}")], 0, y, unit="short", desc="CPU cores used.", fill=0),
    ts("Memory by pod", [tgt(
        'sum by (pod) (container_memory_working_set_bytes{namespace="nhl-odds", container!=""})',
        "{{pod}}")], 12, y, unit="bytes", fill=0),
]
y += 8

nhl.append(row("Scheduled jobs", y)); y += 1
nhl += [
    bargauge("Time since last successful run", [tgt(
        'time() - kube_cronjob_status_last_successful_time{namespace="nhl-odds"}', "{{cronjob}}", instant=True)],
        0, y, w=16, h=7, unit="s",
        th=thresholds((None, "green"), (26 * 3600, "yellow"), (30 * 3600, "red")),
        desc="All jobs run daily; yellow after 26h, red after 30h means a run was missed or failed."),
    stat("Failed jobs (still listed)", [tgt('sum(kube_job_status_failed{namespace="nhl-odds"}) or vector(0)')],
         16, y, w=8, h=7, decimals=0, th=thresholds((None, "green"), (1, "red")), graph=False,
         desc="Failed Job objects kept by the CronJobs' history limits."),
]
y += 7

nhl.append(row("Database & storage", y)); y += 1
nhl += [
    stat("Instances up", [tgt(f"sum(cnpg_collector_up{{{DBSEL}}})")], 0, y, w=4, decimals=0,
         th=thresholds((None, "red"), (1, "yellow"), (2, "green")), graph=False),
    stat("Streaming replicas", [tgt(f"max(cnpg_pg_replication_streaming_replicas{{{DBSEL}}})")], 4, y, w=4,
         decimals=0, th=thresholds((None, "red"), (1, "green")), graph=False),
    stat("Replication lag", [tgt(f"max(cnpg_pg_replication_lag{{{DBSEL}}})")], 8, y, w=4, unit="s",
         th=thresholds((None, "green"), (10, "yellow"), (60, "red"))),
    stat("Database size", [tgt(f'max(cnpg_pg_database_size_bytes{{{DBSEL}, datname="nhl"}})')], 12, y, w=4,
         unit="bytes"),
    stat("Cache hit ratio", [tgt(
        f'sum(rate(cnpg_pg_stat_database_blks_hit{{{DBSEL}, datname="nhl"}}[5m])) / '
        f'clamp_min(sum(rate(cnpg_pg_stat_database_blks_hit{{{DBSEL}, datname="nhl"}}[5m])) + '
        f'sum(rate(cnpg_pg_stat_database_blks_read{{{DBSEL}, datname="nhl"}}[5m])), 1e-9)')],
         16, y, w=4, unit="percentunit", decimals=1,
         th=thresholds((None, "red"), (0.9, "yellow"), (0.99, "green")),
         desc="Share of reads served from shared_buffers. Below ~99% the DB is going to disk."),
    stat("DB volumes not healthy", [tgt(
        'count(longhorn_volume_robustness{pvc_namespace="nhl-odds", state!="healthy"} == 1) or vector(0)')],
         20, y, w=4, graph=False, decimals=0,
         th=thresholds((None, "green"), (1, "red")),
         mappings=[{"type": "value", "options": {"0": {"text": "All healthy", "color": "green"}}}],
         color_mode="background",
         desc="Longhorn volumes for the database that are degraded, faulted or unknown."),
]
y += 4
nhl += [
    ts("Connections", [tgt(
        f'sum by (pod, state) (cnpg_backends_total{{{DBSEL}, datname="nhl", usename!="cnpg_metrics_exporter"}})',
        "{{pod}} {{state}}")], 0, y, w=8, fill=0),
    ts("Transactions / s", [
        tgt(f'sum(rate(cnpg_pg_stat_database_xact_commit{{{DBSEL}, datname="nhl"}}[5m]))', "commit", "A"),
        tgt(f'sum(rate(cnpg_pg_stat_database_xact_rollback{{{DBSEL}, datname="nhl"}}[5m]))', "rollback", "B"),
    ], 8, y, w=8),
    ts("Volume usage", [tgt(
        'kubelet_volume_stats_used_bytes{namespace="nhl-odds"} / kubelet_volume_stats_capacity_bytes{namespace="nhl-odds"}',
        "{{persistentvolumeclaim}}")], 16, y, w=8, unit="percentunit", minv=0, maxv=1, fill=0,
       th=thresholds((None, "green"), (0.75, "yellow"), (0.9, "red")), th_style="dashed"),
]
y += 8

nhl_dash = dashboard(
    "nhl-stack-health", "NHL Stack Health", ["nhl-odds"], nhl,
    "Request rate, response time, workloads, jobs and database for the nhl-odds stack.",
    links=[{"title": "Homelab Nodes", "type": "link", "url": "/d/homelab-nodes", "icon": "dashboard"}],
)

# ---------------------------------------------------------------- Homelab nodes
_id = 0
NODE = "* on (instance) group_left (nodename) node_uname_info"
nodes = []
y = 0
nodes.append(row("Right now", y)); y += 1
PCT_TH = thresholds((None, "green"), (0.7, "yellow"), (0.9, "red"))
nodes += [
    bargauge("CPU", [tgt(f'(1 - avg by (instance) (rate(node_cpu_seconds_total{{mode="idle"}}[5m]))) {NODE}',
                         "{{nodename}}", instant=True)], 0, y, w=5, h=6, unit="percentunit", th=PCT_TH),
    bargauge("Memory", [tgt(f"(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) {NODE}",
                            "{{nodename}}", instant=True)], 5, y, w=5, h=6, unit="percentunit", th=PCT_TH),
    bargauge("Load (1m) per core", [tgt(
        f'(node_load1 / on (instance) count by (instance) (node_cpu_seconds_total{{mode="idle"}})) {NODE}',
        "{{nodename}}", instant=True)], 10, y, w=5, h=6, unit="percentunit", th=PCT_TH,
        desc="1.0 = every core busy."),
    bargauge("Root disk", [tgt(
        f'(1 - node_filesystem_avail_bytes{{mountpoint="/"}} / node_filesystem_size_bytes{{mountpoint="/"}}) {NODE}',
        "{{nodename}}", instant=True)], 15, y, w=4, h=6, unit="percentunit", th=PCT_TH),
    bargauge("CPU temp", [tgt(f'node_thermal_zone_temp{{type="cpu-thermal"}} {NODE}', "{{nodename}}", instant=True)],
             19, y, w=5, h=6, unit="celsius",
             th=thresholds((None, "green"), (65, "yellow"), (80, "red")),
             desc="Pi 5 starts soft-throttling around 80-85°C."),
]
y += 6
nodes += [
    stat("Nodes Ready", [tgt('sum(kube_node_status_condition{condition="Ready", status="true"})')],
         0, y, w=4, h=4, decimals=0, graph=False, th=thresholds((None, "red"), (3, "green"))),
    stat("Pods running", [tgt('sum(kube_pod_status_phase{phase="Running"})')], 4, y, w=4, h=4, decimals=0),
    stat("Pods not healthy", [tgt('sum(kube_pod_status_phase{phase=~"Pending|Failed|Unknown"}) or vector(0)')],
         8, y, w=4, h=4, decimals=0, th=thresholds((None, "green"), (1, "red"))),
    stat("Container restarts (24h)", [tgt("sum(increase(kube_pod_container_status_restarts_total[24h]))")],
         12, y, w=4, h=4, decimals=0, th=thresholds((None, "green"), (1, "yellow"), (5, "red"))),
    bargauge("CPU requested / allocatable", [tgt(
        'sum by (node) (kube_pod_container_resource_requests{resource="cpu"} '
        '* on (namespace, pod) group_left () (kube_pod_status_phase{phase="Running"} == 1)) '
        '/ sum by (node) (kube_node_status_allocatable{resource="cpu"})', "{{node}}", instant=True)],
        16, y, w=4, h=4, unit="percentunit", th=PCT_TH, desc="Scheduling headroom, not actual use."),
    bargauge("Memory requested / allocatable", [tgt(
        'sum by (node) (kube_pod_container_resource_requests{resource="memory"} '
        '* on (namespace, pod) group_left () (kube_pod_status_phase{phase="Running"} == 1)) '
        '/ sum by (node) (kube_node_status_allocatable{resource="memory"})', "{{node}}", instant=True)],
        20, y, w=4, h=4, unit="percentunit", th=PCT_TH, desc="Scheduling headroom, not actual use."),
]
y += 4

nodes.append(row("Over time", y)); y += 1
nodes += [
    ts("CPU usage", [tgt(f'(1 - avg by (instance) (rate(node_cpu_seconds_total{{mode="idle"}}[5m]))) {NODE}',
                         "{{nodename}}")], 0, y, unit="percentunit", minv=0, maxv=1, fill=0,
       legend_calcs=["mean", "max"]),
    ts("Memory usage", [tgt(f"(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) {NODE}",
                            "{{nodename}}")], 12, y, unit="percentunit", minv=0, maxv=1, fill=0,
       legend_calcs=["mean", "max"]),
]
y += 8
nodes += [
    ts("Load average (1m)", [tgt(f"node_load1 {NODE}", "{{nodename}}")], 0, y, w=8, fill=0,
       legend_calcs=["mean", "max"], desc="Each Pi has 4 cores."),
    ts("Temperature", [
        tgt(f'node_thermal_zone_temp{{type="cpu-thermal"}} {NODE}', "{{nodename}} CPU", "A"),
        tgt(f'node_hwmon_temp_celsius{{chip="nvme_nvme0", sensor="temp1"}} {NODE}', "{{nodename}} NVMe", "B"),
    ], 8, y, w=8, unit="celsius", fill=0, legend_calcs=["mean", "max"],
       th=thresholds((None, "green"), (80, "red")), th_style="dashed"),
    ts("Root disk used", [tgt(
        f'(1 - node_filesystem_avail_bytes{{mountpoint="/"}} / node_filesystem_size_bytes{{mountpoint="/"}}) {NODE}',
        "{{nodename}}")], 16, y, w=8, unit="percentunit", minv=0, fill=0),
]
y += 8
nodes += [
    ts("Network received", [tgt(
        f'sum by (instance) (rate(node_network_receive_bytes_total{{device!~"lo|veth.*|cni.*|flannel.*"}}[5m])) {NODE}',
        "{{nodename}}")], 0, y, w=8, unit="Bps", fill=0),
    ts("Network sent", [tgt(
        f'sum by (instance) (rate(node_network_transmit_bytes_total{{device!~"lo|veth.*|cni.*|flannel.*"}}[5m])) {NODE}',
        "{{nodename}}")], 8, y, w=8, unit="Bps", fill=0),
    ts("Disk I/O busy", [tgt(
        f'max by (instance) (rate(node_disk_io_time_seconds_total{{device=~"nvme.*|sd.*|mmcblk.*"}}[5m])) {NODE}',
        "{{nodename}}")], 16, y, w=8, unit="percentunit", minv=0, fill=0,
       desc="Fraction of time the busiest disk had I/O in flight."),
]
y += 8

nodes.append(row("Top consumers", y)); y += 1
nodes += [
    ts("Top 10 pods by CPU", [tgt(
        'topk(10, sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m])))',
        "{{namespace}}/{{pod}}")], 0, y, unit="short", fill=0, desc="CPU cores used."),
    ts("Top 10 pods by memory", [tgt(
        'topk(10, sum by (namespace, pod) (container_memory_working_set_bytes{container!=""}))',
        "{{namespace}}/{{pod}}")], 12, y, unit="bytes", fill=0),
]
y += 8
nodes += [
    ts("CPU by namespace", [tgt(
        'sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))', "{{namespace}}")],
       0, y, unit="short", stack=True, fill=30),
    ts("Memory by namespace", [tgt(
        'sum by (namespace) (container_memory_working_set_bytes{container!=""})', "{{namespace}}")],
       12, y, unit="bytes", stack=True, fill=30),
]

nodes_dash = dashboard(
    "homelab-nodes", "Homelab Nodes", ["homelab"], nodes,
    "Per-node CPU, memory, load, disk, temperature and network for the Pi cluster.",
    refresh="30s", time_from="now-6h",
    links=[{"title": "NHL Stack Health", "type": "link", "url": "/d/nhl-stack-health", "icon": "dashboard"}],
)

os.makedirs(OUT, exist_ok=True)
for name, d in [("nhl-stack-health", nhl_dash), ("homelab-nodes", nodes_dash)]:
    with open(os.path.join(OUT, f"{name}.json"), "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    print(name, len(d["panels"]), "panels")
