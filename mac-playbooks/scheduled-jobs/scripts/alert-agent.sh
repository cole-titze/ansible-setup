#!/bin/bash
# Alert responder, started by launchd (com.coletitze.alert-agent) every minute. Asks Alertmanager
# (through node01, since only ssh/curl reach the LAN under launchd) for the alerts it's sending to
# Discord, and for new ones runs Claude Code headless with alert-agent-prompt.md to investigate and
# apply safe fixes, then posts its report to the same Discord channel and adds next steps to my
# follow-ups list. The session runs in dontAsk mode with ALLOWED_TOOLS: anything not listed is
# refused (no prompt to answer), so the limits don't depend on the prompt. Nodes only through
# homelab-node.sh, which has its own command allowlist.
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

# Alerting itself is down (Alertmanager unreachable, or Prometheus's always-firing Watchdog
# missing): nothing would reach Discord, so say so after DOWN_AFTER, once, and again when it's back.
# node02 hung for 3 days (10-27) with Alertmanager on it and nothing was posted.
DOWN_AFTER=$((10 * 60))
DOWN_SINCE="$STATE_DIR/alerting-down-since"
DOWN_NOTED="$STATE_DIR/alerting-down-noted"
alerting_down() {
  poll_log "$1"
  [ -f "$DOWN_SINCE" ] || date +%s >"$DOWN_SINCE"
  if [ ! -f "$DOWN_NOTED" ] && [ $(($(date +%s) - $(cat "$DOWN_SINCE"))) -ge $DOWN_AFTER ]; then
    discord_post "🔴 Alerting is down" "$1 since $(date -r "$(cat "$DOWN_SINCE")" '+%a %H:%M'), so cluster alerts aren't reaching Discord. Check node01 and the default namespace's alertmanager/prometheus pods." &&
      touch "$DOWN_NOTED"
  fi
  exit 0
}
alerting_up() {
  if [ -f "$DOWN_NOTED" ]; then
    discord_post "✅ Alerting is back" "Alertmanager and Prometheus answer again (down since $(date -r "$(cat "$DOWN_SINCE")" '+%a %H:%M'))."
  fi
  rm -f "$DOWN_SINCE" "$DOWN_NOTED"
}

alerts=$(ssh -i "$HOME/.ssh/node01" -o BatchMode=yes -o ConnectTimeout=10 pi@10.42.0.20 \
  "sudo k3s kubectl get --raw '/api/v1/namespaces/default/services/alertmanager-operated:9093/proxy/api/v2/alerts?active=true&silenced=false&inhibited=false'" 2>>"$POLL_LOG") ||
  alerting_down "Alertmanager can't be reached"
# Watchdog always fires (routed to "null"); without it Prometheus isn't evaluating or sending
watchdog=$(ALERTS="$alerts" python3 -c '
import json, os
alerts = json.loads(os.environ["ALERTS"])
print(sum(a["labels"].get("alertname") == "Watchdog" for a in alerts))' 2>>"$POLL_LOG") || watchdog=0
[ "$watchdog" -gt 0 ] || alerting_down "Prometheus's Watchdog alert is missing (Prometheus down or not sending)"
alerting_up

weekly_running=0
pgrep -f "^/bin/bash .*/scheduled-jobs/scripts/weekly-upgrade.sh" >/dev/null && weekly_running=1

# Prints the alert text for the prompt if a session should run; updates the state files.
# Exit 0 = run, 3 = nothing new, 4 = deferred (weekly), 5 = cap reached (first time today)
decision=$(ALERTS="$alerts" STATE_DIR="$STATE_DIR" STAMP="$STAMP" CAP=$DAILY_CAP COOLDOWN=$COOLDOWN \
  WEEKLY=$weekly_running python3 - <<'EOF'
import json, os, sys, time
d = os.environ["STATE_DIR"]; now = time.time(); stamp = os.environ["STAMP"]
# Only the alerts Alertmanager sends to Discord
alerts = [a for a in json.loads(os.environ["ALERTS"]) if any(r["name"] == "discord" for r in a.get("receivers", []))]
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
NEXT="${LOG%.log}-next.md"
poll_log "session for: $names (log $LOG)"

FOLLOWUPS="$HOME/.claude/projects/-Users-coletitze-source-repos/memory/nhl-roster-repair-followups.md"
# Read-only kubectl, three safe fixes (restart a deployment, delete a stuck pod, re-run a CronJob),
# the node wrapper and text tools. It can only write its report and next-steps files; Claude Code
# won't let it edit ~/.claude, so this script adds the next steps to the follow-ups list.
ALLOWED_TOOLS=(
  "Read(~/**)" "Grep(~/**)" "Glob(~/**)"
  "Edit(~/Library/Logs/homelab/alert-agent-*-report.md)" "Edit(~/Library/Logs/homelab/alert-agent-*-next.md)"
  "Bash(kubectl get:*)" "Bash(kubectl describe:*)" "Bash(kubectl logs:*)" "Bash(kubectl top:*)"
  "Bash(kubectl events:*)" "Bash(kubectl rollout status:*)" "Bash(kubectl rollout history:*)"
  "Bash(kubectl rollout restart:*)" "Bash(kubectl delete pod:*)"
  "Bash(kubectl create job:*)"
  "Bash($SCRIPT_DIR/homelab-node.sh:*)"
  "Bash(gh run list:*)" "Bash(gh run view:*)"
  "Bash(dig:*)" "Bash(ping -c:*)" "Bash(curl -s -o /dev/null -w:*)"
  "Bash(grep:*)" "Bash(jq:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(sort:*)" "Bash(uniq:*)"
  "Bash(wc:*)" "Bash(cut:*)" "Bash(date:*)"
)

# An empty working directory: Claude allows edits anywhere under its working directories, so
# running from ~/source/repos (or --add-dir) would let it edit the repos
WORK_DIR="$STATE_DIR/work"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit 1
start_kube_tunnel 16444

# Subshell, so its exit status (and not an exit of this script) comes out
(
  echo "== Alert agent $(date '+%F %T'): $names"
  claude -p "$(cat "$SCRIPT_DIR/alert-agent-prompt.md")

Alerts:
$decision

Node wrapper: $SCRIPT_DIR/homelab-node.sh
Next-steps file: $NEXT
Write the final report to $REPORT as well as printing it." \
    --permission-mode dontAsk \
    --allowedTools "${ALLOWED_TOOLS[@]}" \
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

# Next steps go into the follow-ups list: "NOW: ..." under Can do now, "LATER: ..." under Later
if [ -s "$NEXT" ] && [ -f "$FOLLOWUPS" ]; then
  NEXT="$NEXT" FOLLOWUPS="$FOLLOWUPS" REPORT_NAME="${REPORT##*/}" python3 - <<'EOF' >>"$POLL_LOG" 2>&1
import os, re
lines = [l.strip() for l in open(os.environ["NEXT"]) if l.strip()]
path = os.environ["FOLLOWUPS"]
text = open(path).read()
added = 0
for l in lines[:3]:
    m = re.match(r"(NOW|LATER):\s*(.+)", l)
    if not m:
        continue
    bullet = f"- {m.group(2)[:400]} (agent report: {os.environ['REPORT_NAME']})\n"
    if m.group(1) == "NOW":
        if "**Can do now:**\n- (none)\n" in text:
            text = text.replace("**Can do now:**\n- (none)\n", "**Can do now:**\n" + bullet, 1)
        else:
            text = text.replace("**Can do now:**\n", "**Can do now:**\n" + bullet, 1)
    else:
        text = text.replace("**Later / discuss:**\n", "**Later / discuss:**\n" + bullet, 1)
    added += 1
if added:
    open(path, "w").write(text)
print(f"added {added} follow-up(s) from {os.environ['NEXT']}")
EOF
fi

if [ -s "$REPORT" ]; then
  discord_post "🤖 Alert agent: $names" "$(cat "$REPORT")"
elif [ $status -ne 0 ]; then
  discord_post "🤖 Alert agent: $names" "Session failed or timed out (exit $status) without a report. Log: $LOG"
else
  discord_post "🤖 Alert agent: $names" "Session finished without writing a report. Log: $LOG"
fi

find "$LOG_DIR" -name 'alert-agent-2*' -mtime +30 -delete
exit 0
