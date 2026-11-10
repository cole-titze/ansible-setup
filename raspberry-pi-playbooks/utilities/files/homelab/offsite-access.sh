#!/bin/sh
# Forced command for the Mac's offsite key in pi's authorized_keys (backup-node-jobs.yml).
# The Mac can only read /home/pi/backups with rsync, and record that its nightly iCloud copy
# finished ("mark-copied"), which the 9:00 stale check reads.
case "${SSH_ORIGINAL_COMMAND:-}" in
  mark-copied) date +%s >/var/lib/homelab/mac-last-copied && echo ok ;;
  *) exec /usr/bin/rrsync -ro /home/pi/backups ;;
esac
