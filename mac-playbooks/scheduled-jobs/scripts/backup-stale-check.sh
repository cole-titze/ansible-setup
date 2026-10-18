#!/bin/bash
# Daily check that the nightly backups actually landed in iCloud, started by launchd
# (com.coletitze.backup-stale-check) at 9:00 CT. Runs separately from nightly-backup.sh so it also
# catches a night when that job never ran (Mac asleep or off). Warns if a backup is over 26 hours old.
set -uo pipefail

BACKUPS="$HOME/source/ansible-files/backups"
LOG_DIR="$HOME/Library/Logs/homelab"
LOG="$LOG_DIR/backup-stale-check.log"
MAX_AGE_HOURS=26
mkdir -p "$LOG_DIR"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

stale=()
# name|newest path matching the glob (by modification time)
for check in "nhl-odds|$BACKUPS/nhl-odds/nhl-*.dump" \
             "macbook|$BACKUPS/macbook/backup_*" \
             "grafana|$BACKUPS/grafana/grafana-*.db"; do
  name="${check%%|*}"
  # shellcheck disable=SC2086
  newest=$(ls -1td ${check#*|} 2>/dev/null | head -1)
  if [ -z "$newest" ]; then
    stale+=("$name: none found")
    continue
  fi
  age_hours=$(( ($(date +%s) - $(stat -f %m "$newest")) / 3600 ))
  if [ "$age_hours" -ge "$MAX_AGE_HOURS" ]; then
    stale+=("$name: ${age_hours}h old")
  fi
  echo "$(date '+%Y-%m-%d %H:%M') $name newest $(basename "$newest") ${age_hours}h" >>"$LOG"
done

if [ ${#stale[@]} -gt 0 ]; then
  msg=$(IFS=', '; echo "${stale[*]}")
  echo "$(date '+%Y-%m-%d %H:%M') STALE: $msg" >>"$LOG"
  notify "Backups are stale" "$msg"
  exit 1
fi

# Keep the log to about 90 days (3 lines a day)
tail -n 270 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
