#!/bin/bash
# Network watchdog, run every minute by net-watchdog.timer (raspberry-pi-setup.yml). node02 lost its
# network on 10-27 and sat unreachable for 3 days: the hardware watchdog never fired because the
# kernel and systemd were still running. This catches that case:
# - The network counts as up while the gateway or any other Pi answers a ping, so a router reboot
#   alone doesn't set off every Pi at once.
# - Down BOUNCE_AFTER minutes in a row: take the uplink down and up (NetworkManager reconnects it).
# - Down REBOOT_AFTER minutes in a row: reboot, unless it booted less than MIN_UPTIME ago or the
#   watchdog already rebooted it within REBOOT_GAP (so a dead switch can't cause a reboot loop).
# Logs to the journal (journalctl -t net-watchdog), which is on disk.
set -uo pipefail

BOUNCE_AFTER=5
REBOOT_AFTER=10
MIN_UPTIME=$((20 * 60))
REBOOT_GAP=$((6 * 3600))
# PEERS: the other Pis' IPs, written by Ansible
[ -f /etc/default/net-watchdog ] && . /etc/default/net-watchdog
PEERS=${PEERS:-}

STATE=/run/net-watchdog-failures            # resets on boot
LAST_REBOOT=/var/lib/net-watchdog/last-reboot
mkdir -p /var/lib/net-watchdog

log() { logger -t net-watchdog "$*"; }

route=$(ip -4 route show default | head -1)
gateway=$(echo "$route" | awk '{print $3}')
uplink=$(echo "$route" | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}')

for target in $gateway $PEERS; do
  if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
    if [ -f "$STATE" ]; then
      log "network back after $(cat "$STATE") minute(s) ($target answers)"
      rm -f "$STATE"
    fi
    exit 0
  fi
done

failures=$(($(cat "$STATE" 2>/dev/null || echo 0) + 1))
echo "$failures" >"$STATE"
log "no answer from gateway ${gateway:-none} or peers ($failures minute(s) in a row)"

if [ "$failures" -eq "$BOUNCE_AFTER" ]; then
  # No default route at all (DHCP lost) falls back to eth0
  uplink=${uplink:-eth0}
  log "bouncing $uplink"
  ip link set "$uplink" down
  sleep 3
  ip link set "$uplink" up
  nmcli device connect "$uplink" >/dev/null 2>&1 || true
elif [ "$failures" -ge "$REBOOT_AFTER" ]; then
  uptime=$(cut -d. -f1 /proc/uptime)
  last=$(cat "$LAST_REBOOT" 2>/dev/null || echo 0)
  if [ "$uptime" -lt "$MIN_UPTIME" ]; then
    log "not rebooting: up only ${uptime}s"
  elif [ $(($(date +%s) - last)) -lt "$REBOOT_GAP" ]; then
    log "not rebooting: the watchdog already rebooted at $(date -d "@$last" '+%F %T')"
  else
    log "rebooting: network down $failures minutes"
    date +%s >"$LAST_REBOOT"
    sync
    systemctl reboot
  fi
fi
