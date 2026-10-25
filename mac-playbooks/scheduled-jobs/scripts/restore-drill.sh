#!/bin/bash
# Weekly restore drill, started by launchd (com.coletitze.restore-drill) on Saturdays at 4:00 CT,
# after the nightly backup (3:10). The drill itself is mac-playbooks/backup/restore-drill.yml:
# launchd's bash can't read iCloud Drive, Ansible's Python can. Notifies either way.
set -uo pipefail

# shellcheck source=common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

REPO="$HOME/source/repos/ansible-setup"
LOG="$LOG_DIR/restore-drill-$(date +%Y-%m-%d).log"

ansible-playbook "$REPO/mac-playbooks/backup/restore-drill.yml" >"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  msg=$(grep -o 'DRILL FAILED: [^"]*' "$LOG" | tail -1)
  notify "Restore drill FAILED" "${msg:-Exit $status. See $LOG}"
  discord_post "❌ Restore drill FAILED" "${msg:-Exit $status.} Log: $LOG" "$LOG"
else
  notify "Restore drill passed" "nhl-odds, Grafana and MacBook backups check out. See $LOG"
  # The playbook's per-backup result lines ("nhl-odds: ...", "grafana: ...", "macbook: ...", "vault: ...")
  discord_post "✅ Restore drill passed" "$(grep -oE '"msg": "(nhl-odds|grafana|macbook|vault): [^"]*' "$LOG" | sed 's/"msg": "//')"
fi

find "$LOG_DIR" -name 'restore-drill-*.log' -mtime +90 -delete
exit $status
