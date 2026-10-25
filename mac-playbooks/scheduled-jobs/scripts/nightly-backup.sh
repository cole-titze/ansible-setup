#!/bin/bash
# Nightly Mac backup, started by launchd (com.coletitze.nightly-backup) at 3:10 CT.
# Runs after the cluster's own backups: nhl-odds dump 1:00, Grafana 1:30, kured reboots 2:00-2:55.
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
