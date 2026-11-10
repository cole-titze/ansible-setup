#!/bin/bash
# Runs one ansible-setup playbook on the backup Pi, for the Remote Control session (CLAUDE.md
# says to use this instead of calling ansible-playbook directly). One run at a time (a second one
# waits for the lock), and every run is logged to /var/log/homelab/runs/.
#   homelab-run <playbook.yml> [ansible-playbook options, e.g. -t traefik --check --diff]
# Installed by backup-node-remote-control.yml.
set -uo pipefail

REPO=/home/pi/source/repos/ansible-setup
RUN_DIR=/var/log/homelab/runs
LOCK=/run/lock/homelab-run.lock

[ $# -ge 1 ] || { echo "usage: homelab-run <playbook.yml> [ansible-playbook options]" >&2; exit 2; }
playbook=$1; shift
cd "$REPO" || exit 1
[ -f "$playbook" ] || { echo "no playbook $playbook under $REPO" >&2; exit 2; }

log="$RUN_DIR/$(date +%Y-%m-%d-%H%M%S)-$(basename "$playbook" .yml).log"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "another homelab-run is going; waiting for it to finish..."
  flock 9
fi
{
  echo "== $(date '+%F %T') homelab-run $playbook $* (commit $(git rev-parse --short HEAD))"
  ansible-playbook -i inventories/inventory.ini "$playbook" "$@"
  status=$?
  echo "== $(date '+%F %T') exit $status"
  exit $status
} 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
find "$RUN_DIR" -name '*.log' -mtime +90 -delete
exit $status
