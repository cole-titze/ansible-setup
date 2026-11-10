#!/bin/bash
# Daily check that the backups reached the backup Pi and the Mac's iCloud copy, started by
# homelab-backup-stale-check.timer at 9:00 CT (backup-node-jobs.yml). Posts to Discord when:
# - the newest nhl-odds dump or Grafana DB here is MAX_HOURS old or missing (4:00 pull failed)
# - the Mac hasn't copied them to iCloud for MAC_MAX_HOURS (asleep, off, at the login screen)
set -uo pipefail
. /usr/local/lib/homelab/common.sh

BACKUPS=/home/pi/backups
MARKER=/var/lib/homelab/mac-last-copied
MAX_HOURS=26
MAC_MAX_HOURS=48
LOG="$LOG_DIR/backup-stale-check-$(date +%Y-%m-%d).log"
now=$(date +%s)
stale=()

# check <name> <dir> <glob>: names are dated, so the newest is last by name
check() {
  local newest age
  newest=$(ls -1 "$2"/$3 2>/dev/null | sort | tail -1)
  if [ -z "$newest" ]; then
    stale+=("$1 none found"); echo "$1: none found"; return
  fi
  age=$(((now - $(stat -c %Y "$newest")) / 3600))
  echo "$1: $(basename "$newest"), ${age}h old"
  [ $age -lt $MAX_HOURS ] || stale+=("$1 ${age}h old")
}

{
  echo "== Backup stale check $(date '+%F %T')"
  check nhl-odds "$BACKUPS/nhl-odds" 'nhl-????-??-??.dump'
  check grafana "$BACKUPS/grafana" 'grafana-*.db'
  if [ -s "$MARKER" ]; then
    copied=$(cat "$MARKER")
    age=$(((now - copied) / 3600))
    echo "mac copy: $(date -d "@$copied" '+%F %T'), ${age}h ago"
    [ $age -lt $MAC_MAX_HOURS ] || stale+=("Mac's iCloud copy ${age}h old (last $(date -d "@$copied" '+%a %b %-d %H:%M'))")
  else
    echo "mac copy: never"
    stale+=("Mac's iCloud copy never ran")
  fi
} >>"$LOG" 2>&1

status=0
if [ ${#stale[@]} -gt 0 ]; then
  msg="STALE: $(IFS=,; echo "${stale[*]}" | sed 's/,/, /g')"
  echo "$msg" >>"$LOG"
  discord_post "⚠️ Backups are stale (backup Pi)" "$msg. Log: $(hostname):$LOG"
  status=1
fi

find "$LOG_DIR" -name 'backup-stale-check-*.log' -mtime +30 -delete
exit $status
