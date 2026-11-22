#!/usr/bin/env python3
"""Temperature-controlled USB fans on node01 (utilities/node01-fans.yml).

Runs every minute as root. The two Noctua fans are plugged into node01's USB ports, and nothing
else is: a Pi 5 can only switch all four USB ports together (uhubctl), so this is safe only while
the ports hold nothing but fans. Reads every Pi's CPU temperature from Prometheus (node01's own
from sysfs), turns the fans on if any Pi passes its "on" limit and off once every Pi is back under
its "off" limit.

Fail-safe: fans on if Prometheus can't be reached or a Pi has no reading. A reboot also powers
the ports (fans on) until the first run.
Discord: once when a Pi stays hot for 15 min with the fans on, once when Prometheus is unreachable
for 10 min, and once when each clears.
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

# nodename -> (on at, off at) in °C. The backup Pi is a Pi 4 that throttles at 75 (temp_limit);
# the Pi 5s throttle at 85.
LIMITS = {
    "dockerpibackup": (65.0, 58.0),
    "node01": (72.0, 64.0),
    "node02": (72.0, 64.0),
    "node03": (72.0, 64.0),
    "node04": (72.0, 64.0),
}
SELF = "node01"
# uhubctl hub locations of a Pi 5's onboard ports (USB2 + USB3 halves). Power goes off only when
# both are off; turning either on powers all four ports.
HUBS = ["2", "4"]
PROM_SVC = ("default", "cluster-monitoring-kube-pr-prometheus")
QUERY = "max by (nodename) (node_thermal_zone_temp{type='cpu-thermal'} * on(instance) group_left(nodename) node_uname_info)"
STATE_FILE = "/var/lib/homelab-fans/state.json"
WEBHOOK_FILE = "/etc/homelab/discord-webhook"
HOT_ALERT_MIN = 15
PROM_ALERT_MIN = 10


def log(msg):
    print(msg, flush=True)


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_FILE)


def discord(title, text):
    try:
        with open(WEBHOOK_FILE) as f:
            url = f.read().strip()
        body = json.dumps({"content": f"**{title}**\n{text}"[:2000]}).encode()
        req = urllib.request.Request(url, body, {"Content-Type": "application/json", "User-Agent": "homelab-fans"})
        urllib.request.urlopen(req, timeout=20).read()
    except Exception as e:  # never let an alert failure stop the fan control
        log(f"Discord post failed ({title}): {e}")


def prom_ip(state):
    """Prometheus's ClusterIP (node01 reaches services directly); cached for when the API is down."""
    try:
        ip = subprocess.run(
            ["kubectl", "-n", PROM_SVC[0], "get", "svc", PROM_SVC[1], "-o", "jsonpath={.spec.clusterIP}"],
            capture_output=True, text=True, timeout=20,
            env={**os.environ, "KUBECONFIG": "/etc/rancher/k3s/k3s.yaml"},
        ).stdout.strip()
        if ip:
            state["prom_ip"] = ip
    except (OSError, subprocess.SubprocessError):
        pass
    return state.get("prom_ip")


def remote_temps(state):
    ip = prom_ip(state)
    if not ip:
        raise RuntimeError("no Prometheus service IP")
    url = f"http://{ip}:9090/api/v1/query?" + urllib.parse.urlencode({"query": QUERY})
    with urllib.request.urlopen(url, timeout=15) as r:
        data = json.load(r)
    out = {}
    for row in data["data"]["result"]:
        # Ignore samples older than 3 min (a Pi that stopped reporting counts as missing)
        ts, val = row["value"]
        if time.time() - float(ts) < 180:
            out[row["metric"]["nodename"]] = float(val)
    return out


def local_temp():
    with open("/sys/class/thermal/thermal_zone0/temp") as f:
        return int(f.read()) / 1000


def set_fans(on):
    for hub in HUBS:
        subprocess.run(["uhubctl", "-l", hub, "-a", "1" if on else "0"],
                       capture_output=True, timeout=30, check=True)


def main():
    state = load_state()
    now = time.time()
    fans_were_on = state.get("on", True)
    temps, problems = {}, []

    try:
        temps = remote_temps(state)
        if state.pop("prom_down_since", None) and state.pop("prom_alerted", False):
            discord("Fan control: Prometheus back", "node01 reads Pi temperatures again.")
    except Exception as e:
        problems.append(f"Prometheus: {e}")
        state.setdefault("prom_down_since", now)
        if not state.get("prom_alerted") and now - state["prom_down_since"] >= PROM_ALERT_MIN * 60:
            discord("Fan control: Prometheus unreachable",
                    f"node01 can't read Pi temperatures for {PROM_ALERT_MIN}+ min ({e}); fans forced on.")
            state["prom_alerted"] = True
    try:
        temps[SELF] = local_temp()
    except OSError as e:
        problems.append(f"{SELF} sysfs: {e}")

    missing = [n for n in LIMITS if n not in temps]
    if missing:
        problems.append("no reading: " + ", ".join(missing))

    hot = [n for n, t in temps.items() if n in LIMITS and t >= LIMITS[n][0]]
    warm = [n for n, t in temps.items() if n in LIMITS and t > LIMITS[n][1]]
    if problems or hot:
        on = True
    elif fans_were_on:
        on = bool(warm)  # stay on until every Pi is under its "off" limit
    else:
        on = False

    set_fans(on)
    summary = " ".join(f"{n}={temps[n]:.1f}" for n in sorted(temps))
    if on != fans_were_on or "on" not in state:
        why = "; ".join(problems) or (f"hot: {', '.join(hot)}" if hot else f"warm: {', '.join(warm)}" if on else "all cool")
        log(f"fans {'ON' if on else 'OFF'} ({why}) {summary}")
    state["on"] = on

    # Hot with the fans running: the fans aren't keeping up
    if hot:
        state.setdefault("hot_since", now)
        if not state.get("hot_alerted") and now - state["hot_since"] >= HOT_ALERT_MIN * 60:
            discord("Pi still hot with fans on",
                    f"Over the limit for {HOT_ALERT_MIN}+ min: {', '.join(f'{n} {temps[n]:.1f}°C' for n in hot)}")
            state["hot_alerted"] = True
    else:
        if state.pop("hot_since", None) and state.pop("hot_alerted", False):
            discord("Pi temperatures back to normal", summary)

    save_state(state)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        log(f"error: {e}; forcing fans on")
        try:
            set_fans(True)
        finally:
            sys.exit(1)
