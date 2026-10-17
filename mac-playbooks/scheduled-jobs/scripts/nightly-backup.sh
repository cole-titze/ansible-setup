#!/bin/bash
# Nightly Mac backup, started by launchd (com.coletitze.nightly-backup) at 3:10 CT.
# Runs after the cluster's own backups: nhl-odds dump 1:00, Grafana 1:30, kured reboots 2:00-2:55.
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES   # Python fork crashes on macOS, see macbook-setup.md

REPO="$HOME/source/repos/ansible-setup"
LOG_DIR="$HOME/Library/Logs/homelab"
LOG="$LOG_DIR/nightly-backup-$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

{
  echo "== Nightly backup $(date '+%Y-%m-%d %H:%M:%S')"
  cd "$REPO" || exit 1
  git pull --ff-only --quiet || echo "WARN: git pull failed, using the current checkout"
  bash mac-playbooks/backup/scripts/Backup.sh
} >>"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  notify "Nightly backup FAILED" "Exit $status. See $LOG"
else
  echo "== Done $(date '+%H:%M:%S')" >>"$LOG"
fi

# Keep 30 days of logs
find "$LOG_DIR" -name 'nightly-backup-*.log' -mtime +30 -delete
exit $status
