#!/bin/bash
# Alert responder, started by launchd (com.coletitze.alert-agent) every minute. Asks Alertmanager
# (through node01, since only ssh/curl reach the LAN under launchd) for the alerts it's sending to
# Discord, and for new ones runs Claude Code headless with alert-agent-prompt.md to investigate and
# fix them, then posts its report to the same Discord channel.
# - One session per poll for all new alerts (one incident often fires several).
# - An alert counts once (fingerprint + start time), so the 12h Discord repeats don't re-run it;
#   the same alertname waits COOLDOWN after a run; at most DAILY_CAP sessions a day.
# - New alerts wait while the weekly upgrade runs (its upgrades fire alerts and it edits the same repos).
# - launchd doesn't start the job again while it's still running, so sessions never overlap.
# - First run only records what's already firing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

DAILY_CAP=5
COOLDOWN=$((2 * 3600))
SESSION_TIMEOUT=$((45 * 60))
STATE_DIR="$HOME/Library/Application Support/homelab/alert-agent"
STAMP="$(date +%Y-%m-%d)"
POLL_LOG="$LOG_DIR/alert-agent-poll.log"
mkdir -p "$STATE_DIR"

poll_log() { echo "$(date '+%F %T') $*" >>"$POLL_LOG"; }

alerts=$(ssh -i "$HOME/.ssh/node01" -o BatchMode=yes -o ConnectTimeout=10 pi@10.42.0.20 \
  "sudo k3s kubectl get --raw '/api/v1/namespaces/default/services/alertmanager-operated:9093/proxy/api/v2/alerts?active=true&silenced=false&inhibited=false&receiver=discord'" 2>>"$POLL_LOG") || {
  poll_log "couldn't reach Alertmanager"
  exit 0
}

weekly_running=0
pgrep -f "^/bin/bash .*/scheduled-jobs/scripts/weekly-upgrade.sh" >/dev/null && weekly_running=1

# Prints the alert text for the prompt if a session should run; updates the state files.
# Exit 0 = run, 3 = nothing new, 4 = deferred (weekly), 5 = cap reached (first time today)
decision=$(ALERTS="$alerts" STATE_DIR="$STATE_DIR" STAMP="$STAMP" CAP=$DAILY_CAP COOLDOWN=$COOLDOWN \
  WEEKLY=$weekly_running python3 - <<'EOF'
import json, os, sys, time
d = os.environ["STATE_DIR"]; now = time.time(); stamp = os.environ["STAMP"]
alerts = json.loads(os.environ["ALERTS"])
def load(name, default):
    try:
        with open(os.path.join(d, name)) as f: return json.load(f)
    except (OSError, ValueError): return default
def save(name, value):
    tmp = os.path.join(d, name + ".tmp")
    with open(tmp, "w") as f: json.dump(value, f)
    os.replace(tmp, os.path.join(d, name))

first_run = not os.path.exists(os.path.join(d, "seen.json"))
seen = load("seen.json", {})
last_run = load("last-run.json", {})
runs = load("runs.json", {})
active = {a["fingerprint"] + "@" + a["startsAt"]: a for a in alerts}
new = [a for k, a in active.items() if k not in seen]
# Forget alerts that stopped firing, so a later re-fire counts as new
seen = {k: v for k, v in seen.items() if k in active}

def done(code):
    save("seen.json", seen); save("last-run.json", last_run); save("runs.json", runs)
    sys.exit(code)

if first_run or not new:
    seen.update({k: now for k in active}); done(3)
if os.environ["WEEKLY"] == "1":
    done(4)  # not marked seen: picked up after the weekly run
for a in new:
    seen[a["fingerprint"] + "@" + a["startsAt"]] = now
fresh = [a for a in new if now - last_run.get(a["labels"].get("alertname", ""), 0) > int(os.environ["COOLDOWN"])]
if not fresh:
    done(3)
runs = {stamp: runs.get(stamp, 0)}
if runs[stamp] >= int(os.environ["CAP"]):
    noted = load("cap-noted.json", "")
    save("cap-noted.json", stamp)
    print(", ".join(sorted({a["labels"].get("alertname", "?") for a in fresh})))
    done(5 if noted != stamp else 3)
runs[stamp] += 1
for a in fresh:
    last_run[a["labels"].get("alertname", "")] = now
# Only cluster-generated fields (labels, summary, runbook link): never raw log text
for a in fresh:
    labels = a["labels"]; ann = a.get("annotations", {})
    print(f"- {labels.get('alertname')} ({labels.get('severity')}), firing since {a['startsAt']}")
    print(f"  summary: {ann.get('summary', '')}")
    if ann.get("runbook_url"): print(f"  runbook: {ann['runbook_url']}")
    print("  labels: " + ", ".join(f"{k}={v}" for k, v in sorted(labels.items()) if k not in ("alertname", "severity")))
done(0)
EOF
)
rc=$?
case $rc in
  0) ;;
  3) exit 0 ;;
  4) poll_log "new alert(s) wait for the weekly upgrade to finish"; exit 0 ;;
  5) poll_log "daily cap reached"
     discord_post "🤖 Alert agent: daily cap reached" "$DAILY_CAP sessions ran today, so I'm not investigating $decision. Alerts still come here; the agent starts again tomorrow."
     exit 0 ;;
  *) poll_log "state update failed (exit $rc)"; exit 0 ;;
esac

names=$(echo "$decision" | sed -n 's/^- \([^ ]*\) .*/\1/p' | sort -u | paste -sd, - | sed 's/,/, /g')
LOG="$LOG_DIR/alert-agent-$(date +%Y-%m-%d-%H%M).log"
REPORT="${LOG%.log}-report.md"
poll_log "session for: $names (log $LOG)"

cd "$HOME/source/repos" || exit 1
start_cluster_env 16444

# Subshell, so its exit status (and not an exit of this script) comes out
(
  echo "== Alert agent $(date '+%F %T'): $names"
  claude -p "$(cat "$SCRIPT_DIR/alert-agent-prompt.md")

Alerts:
$decision

Write the final report to $REPORT as well as printing it." \
    --permission-mode bypassPermissions \
    --add-dir "$HOME/.claude/skills" \
    --add-dir "$ANSIBLE_FILES_PATH" \
    --output-format stream-json --verbose &
  claude_pid=$!
  ( sleep "$SESSION_TIMEOUT"; kill "$claude_pid" 2>/dev/null ) &
  watchdog_pid=$!
  wait "$claude_pid"
  status=$?
  kill "$watchdog_pid" 2>/dev/null
  exit $status
) >>"$LOG" 2>&1
status=$?

if [ -s "$REPORT" ]; then
  discord_post "🤖 Alert agent: $names" "$(cat "$REPORT")"
elif [ $status -ne 0 ]; then
  discord_post "🤖 Alert agent: $names" "Session failed or timed out (exit $status) without a report. Log: $LOG"
else
  discord_post "🤖 Alert agent: $names" "Session finished without writing a report. Log: $LOG"
fi

find "$LOG_DIR" -name 'alert-agent-2*' -mtime +30 -delete
exit 0
