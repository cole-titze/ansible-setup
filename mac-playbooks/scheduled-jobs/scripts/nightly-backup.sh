#!/bin/bash
# Nightly Mac backup, started by launchd (com.coletitze.nightly-backup) at 4:30 CT.
# Copies the backup Pi's nhl-odds dumps and Grafana DBs (pulled off the cluster at 4:00) into iCloud,
# checks them against the Pi's checksums and tells the Pi the copy is done, then backs up the Mac.
set -uo pipefail

# shellcheck source=common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

REPO="$HOME/source/repos/ansible-setup"
LOG="$LOG_DIR/nightly-backup-$(date +%Y-%m-%d).log"

{
  echo "== Nightly backup $(date '+%Y-%m-%d %H:%M:%S')"
  cd "$REPO" || exit 1
  git pull --ff-only --quiet || echo "WARN: git pull failed, using the current checkout"
  bash mac-playbooks/backup/scripts/Backup.sh
} >>"$LOG" 2>&1
status=$?

# The backup Pi's alert agent writes next steps to ~pi/backups/alert-agent/next-steps.txt
# ("<run>\tNOW: ..." / "<run>\tLATER: ..."); add new ones to my follow-ups list
# ("NOW" under Can do now, "LATER" under Later), once per run name.
merge_pi_next_steps() {
  local list="$HOME/source/backups/alert-agent-next-steps.txt"
  /usr/bin/rsync -t -e "ssh -i $HOME/.ssh/backuppi_offsite -o BatchMode=yes -o ConnectTimeout=10" \
    pi@10.42.0.3:alert-agent/next-steps.txt "$list" 2>/dev/null || return 0
  LIST="$list" STATE="$HOME/Library/Application Support/homelab/alert-agent/merged-pi-runs.json" \
    FOLLOWUPS="$HOME/.claude/projects/-Users-coletitze-source-repos/memory/nhl-roster-repair-followups.md" python3 - <<'PY'
import json, os, re
state, path = os.environ["STATE"], os.environ["FOLLOWUPS"]
try:
    merged = set(json.load(open(state)))
except (OSError, ValueError):
    merged = set()
text = open(path).read()
added, runs = 0, set()
for line in open(os.environ["LIST"]):
    run, _, rest = line.rstrip("\n").partition("\t")
    m = re.match(r"(NOW|LATER):\s*(.+)", rest)
    if not m or run in merged:
        continue
    runs.add(run)
    bullet = f"- {m.group(2)[:400]} (Pi agent report: {run}-report.md)\n"
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
os.makedirs(os.path.dirname(state), exist_ok=True)
json.dump(sorted(merged | runs)[-500:], open(state, "w"))
print(f"added {added} follow-up(s) from the Pi's alert agent")
PY
}
[ $status -eq 0 ] && merge_pi_next_steps >>"$LOG" 2>&1

if [ $status -ne 0 ]; then
  notify "Nightly backup FAILED" "Exit $status. See $LOG"
  discord_post "❌ Nightly Mac backup FAILED (exit $status)" "$(tail -15 "$LOG")" "$LOG"
else
  echo "== Done $(date '+%H:%M:%S')" >>"$LOG"
fi

# Keep 30 days of logs
find "$LOG_DIR" -name 'nightly-backup-*.log' -mtime +30 -delete
exit $status
