#!/bin/sh
# Pulls the cluster's nightly backups onto the backup Pi so a copy lives off the cluster:
# - today's nhl-odds dump (every worker dumps the same DB at 1:00, so the first worker that has it wins)
# - Grafana DBs (the grafana-db-backup CronJob writes to whichever worker runs Grafana, so all of them)
# Each folder gets a SHA256SUMS that the Mac's nightly copy checks its iCloud copies against.
# Usage: nhl-backup-pull.sh <worker-ip>...
set -u

BACKUPS=/home/pi/backups
NHL_KEEP=30
GRAFANA_KEEP=35
KEY=/root/.ssh/nhl_backup_pull
# node exporter's textfile collector (backup-node-exporter.yml); BackupPiDbPullStale alerts on it
METRIC=/var/lib/prometheus/node-exporter/nhl_backup_pull.prom
FILE="nhl-$(date +%Y-%m-%d).dump"
SSH="ssh -i $KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

log() { echo "$(date '+%F %T') $*"; }

# keep_newest <dir> <glob> <n>: names are dated, so a reverse sort puts the newest first
keep_newest() {
  ls -1 "$1"/$2 2>/dev/null | sort -r | tail -n +$(($3 + 1)) | xargs -r rm -f
}

# update_sums <dir> <glob>: SHA256SUMS lists every matching file. Only new files get hashed.
# Partial transfers stay in .rsync-partial, so a listed name is always a finished file.
update_sums() {
  (
    cd "$1" || exit 1
    touch SHA256SUMS
    while read -r sum name; do
      [ -f "$name" ] && echo "$sum  $name"
    done <SHA256SUMS >SHA256SUMS.tmp
    for f in $2; do
      [ -f "$f" ] || continue
      grep -q "  $f\$" SHA256SUMS.tmp || sha256sum "$f" >>SHA256SUMS.tmp
    done
    sort -k2 SHA256SUMS.tmp >SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS
    rm -f SHA256SUMS.tmp
    chmod 644 SHA256SUMS
  )
}

mkdir -p "$BACKUPS/nhl-odds" "$BACKUPS/grafana"
status=1

# ---- nhl-odds ------------------------------------------------------------------------------
for host in "$@"; do
  # Workers restrict this key to read-only rrsync rooted at their backups dir
  if rsync -t --partial-dir=.rsync-partial -e "$SSH" "pi@$host:nhl-odds/$FILE" "$BACKUPS/nhl-odds/"; then
    log "pulled $FILE from $host ($(du -h "$BACKUPS/nhl-odds/$FILE" | cut -f1))"
    keep_newest "$BACKUPS/nhl-odds" 'nhl-????-??-??.dump' $NHL_KEEP
    if [ -d "${METRIC%/*}" ]; then
      echo "nhl_backup_pull_last_success_timestamp_seconds $(date +%s)" > "$METRIC.tmp" && mv "$METRIC.tmp" "$METRIC"
    fi
    status=0
    break
  fi
  log "$host: pull failed, trying the next worker"
done
[ $status -eq 0 ] || log "ERROR: no worker had $FILE"
update_sums "$BACKUPS/nhl-odds" 'nhl-????-??-??.dump'

# ---- Grafana -------------------------------------------------------------------------------
# A worker that has never run the CronJob has no grafana folder; that's not an error
for host in "$@"; do
  rsync -rt --partial-dir=.rsync-partial --include='grafana-*.db' --exclude='*' -e "$SSH" \
    "pi@$host:grafana/" "$BACKUPS/grafana/" 2>/dev/null && log "grafana: synced from $host"
done
keep_newest "$BACKUPS/grafana" 'grafana-*.db' $GRAFANA_KEEP
update_sums "$BACKUPS/grafana" 'grafana-*.db'
log "grafana: newest $(ls -1 "$BACKUPS"/grafana/grafana-*.db 2>/dev/null | sort | tail -1 | xargs -r basename)"

exit $status
