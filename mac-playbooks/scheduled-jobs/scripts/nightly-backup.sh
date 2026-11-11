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

if [ $status -ne 0 ]; then
  notify "Nightly backup FAILED" "Exit $status. See $LOG"
  discord_post "❌ Nightly Mac backup FAILED (exit $status)" "$(tail -15 "$LOG")" "$LOG"
else
  echo "== Done $(date '+%H:%M:%S')" >>"$LOG"
fi

# Keep 30 days of logs
find "$LOG_DIR" -name 'nightly-backup-*.log' -mtime +30 -delete
exit $status
