#!/bin/bash
# The alert agent's only way onto the Pis: runs one allowlisted command on a node over ssh.
#   homelab-node.sh <node01|node02|node03|node04|dockerpibackup> <command...>
# Read-only checks, plus restarting a few exporter/DNS services (the agent's "safe fixes").
# Anything else, or any shell metacharacter, is refused, so the agent's Bash allowlist can
# include this script without giving it a shell on the nodes.
set -uo pipefail

case "${1:-}" in
  node01) ip=10.42.0.20; key=node01 ;;
  node02) ip=10.42.0.21; key=node02 ;;
  node03) ip=10.42.0.22; key=node03 ;;
  node04) ip=10.42.0.2; key=node04 ;;
  dockerpibackup) ip=10.42.0.3; key=dockerpibackup ;;
  *) echo "usage: $0 <node01|node02|node03|node04|dockerpibackup> <command...>" >&2; exit 2 ;;
esac
shift
cmd="$*"

if [[ "$cmd" =~ [\;\|\&\`\$\(\)\<\>\\\'\"] ]] || [[ "$cmd" == *$'\n'* ]]; then
  echo "refused: shell metacharacters aren't allowed" >&2; exit 2
fi

unit='(prometheus-node-exporter|smartctl-exporter|pihole-FTL|unbound|k3s|k3s-agent|dnspi-firewall|cron|ssh)'
restartable='(prometheus-node-exporter|smartctl-exporter|pihole-FTL|unbound)'
logfile='/var/log/(pihole-failover|nhl-backup-pull|syslog|pihole/pihole|pihole/FTL)\.log'
allowed=(
  "uptime"
  "free -[hm]"
  "df -h( [a-z/]+)?"
  "systemctl (status|is-active|is-enabled) $unit( --no-pager)?"
  "systemctl --failed( --no-pager)?"
  "journalctl -u $unit( -n [0-9]+| --since [0-9a-z:-]+| --no-pager)*"
  "journalctl -p (err|warning)( -n [0-9]+| --since [0-9a-z:-]+| -b| --no-pager)*"
  "tail -n [0-9]+ $logfile"
  "ls -l[ah]* /home/pi/backups/nhl-odds"
  "vcgencmd (measure_temp|get_throttled)"
  "pihole status"
  "pihole-FTL --config dhcp.active"
  "dig @127.0.0.1 [a-z0-9.-]+( \+short)?"
  "cat /proc/loadavg"
  "ls /var/run/reboot-required"
  "systemctl restart $restartable"
)

for re in "${allowed[@]}"; do
  if [[ "$cmd" =~ ^${re}$ ]]; then
    exec ssh -i "$HOME/.ssh/$key" -o BatchMode=yes -o ConnectTimeout=10 "pi@$ip" "sudo $cmd"
  fi
done
echo "refused: '$cmd' isn't on the allowlist in $0" >&2
exit 2
