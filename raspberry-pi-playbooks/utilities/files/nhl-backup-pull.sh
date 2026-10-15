#!/bin/sh
# Pulls today's nhl-odds dump from a K3s worker so a copy lives off the cluster.
# Every worker dumps the same DB at 1:00, so the first worker that has today's file wins.
# Usage: nhl-backup-pull.sh <worker-ip>...
set -u

DEST=/home/pi/backups/nhl-odds
KEEP=30
KEY=/root/.ssh/nhl_backup_pull
FILE="nhl-$(date +%Y-%m-%d).dump"

log() { echo "$(date '+%F %T') $*"; }

mkdir -p "$DEST"
for host in "$@"; do
  # Workers restrict this key to read-only rrsync rooted at their dump dir, so paths are bare file names
  if rsync -t --partial \
      -e "ssh -i $KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10" \
      "pi@$host:$FILE" "$DEST/"; then
    log "pulled $FILE from $host ($(du -h "$DEST/$FILE" | cut -f1))"
    # Names are dated, so a reverse sort puts the newest first
    ls -1 "$DEST"/nhl-????-??-??.dump | sort -r | tail -n +$((KEEP + 1)) | xargs -r rm -f
    exit 0
  fi
  log "$host: pull failed, trying the next worker"
done

log "ERROR: no worker had $FILE"
exit 1
