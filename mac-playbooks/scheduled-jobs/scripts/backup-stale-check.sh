#!/bin/bash
# Daily check that the nightly backups actually landed in iCloud, started by launchd
# (com.coletitze.backup-stale-check) at 9:00 CT. Runs separately from nightly-backup.sh so it also
# catches a night when that job never ran (Mac asleep or off). The check itself is
# mac-playbooks/backup/backup-stale-check.yml: launchd's bash can't read iCloud Drive, Ansible's Python can.
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES   # Python fork crashes on macOS, see macbook-setup.md

REPO="$HOME/source/repos/ansible-setup"
LOG_DIR="$HOME/Library/Logs/homelab"
LOG="$LOG_DIR/backup-stale-check-$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

ansible-playbook "$REPO/mac-playbooks/backup/backup-stale-check.yml" >"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  msg=$(grep -o 'STALE: [^"]*' "$LOG" | tail -1)
  notify "Backups are stale" "${msg:-Check failed (exit $status). See $LOG}"
fi

find "$LOG_DIR" -name 'backup-stale-check-*.log' -mtime +30 -delete
exit $status
