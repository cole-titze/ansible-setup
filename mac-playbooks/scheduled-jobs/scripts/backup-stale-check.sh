#!/bin/bash
# Daily check that the nightly backups actually landed in iCloud, started by launchd
# (com.coletitze.backup-stale-check) at 9:00 CT. Runs separately from nightly-backup.sh so it also
# catches a night when that job never ran (Mac asleep or off). The check itself is
# mac-playbooks/backup/backup-stale-check.yml: launchd's bash can't read iCloud Drive, Ansible's Python can.
set -uo pipefail

# shellcheck source=common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

REPO="$HOME/source/repos/ansible-setup"
LOG="$LOG_DIR/backup-stale-check-$(date +%Y-%m-%d).log"

ansible-playbook "$REPO/mac-playbooks/backup/backup-stale-check.yml" >"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  msg=$(grep -o 'STALE: [^"]*' "$LOG" | tail -1)
  notify "Backups are stale" "${msg:-Check failed (exit $status). See $LOG}"
  discord_post "⚠️ Backups are stale" "${msg:-Check failed (exit $status).} Log: $LOG"
fi

find "$LOG_DIR" -name 'backup-stale-check-*.log' -mtime +30 -delete
exit $status
