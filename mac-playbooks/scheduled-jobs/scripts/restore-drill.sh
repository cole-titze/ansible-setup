#!/bin/bash
# Weekly restore drill, started by launchd (com.coletitze.restore-drill) on Saturdays at 4:00 CT,
# after the nightly backup (3:10). The drill itself is mac-playbooks/backup/restore-drill.yml:
# launchd's bash can't read iCloud Drive, Ansible's Python can. Notifies either way.
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES   # Python fork crashes on macOS, see macbook-setup.md

REPO="$HOME/source/repos/ansible-setup"
LOG_DIR="$HOME/Library/Logs/homelab"
LOG="$LOG_DIR/restore-drill-$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

ansible-playbook "$REPO/mac-playbooks/backup/restore-drill.yml" >"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  msg=$(grep -o 'DRILL FAILED: [^"]*' "$LOG" | tail -1)
  notify "Restore drill FAILED" "${msg:-Exit $status. See $LOG}"
else
  notify "Restore drill passed" "nhl-odds, Grafana and MacBook backups check out. See $LOG"
fi

find "$LOG_DIR" -name 'restore-drill-*.log' -mtime +90 -delete
exit $status
