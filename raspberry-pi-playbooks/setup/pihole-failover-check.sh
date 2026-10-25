#!/bin/bash

PRIMARY_IP="10.42.0.2"
TIMEOUT=2
# Consecutive failed checks (one per minute) before DHCP is taken over, so a
# single dropped ping doesn't flap DHCP on and off.
FAIL_THRESHOLD=3
# /run is tmpfs, so the count starts at 0 after a reboot.
STATE_FILE="/run/pihole-failover-fails"
# node exporter's textfile collector (backup-node-exporter.yml); PiholeFailoverActive alerts on it
METRIC="/var/lib/prometheus/node-exporter/pihole_failover.prom"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

CURRENT=$(/usr/bin/pihole-FTL --config dhcp.active 2>/dev/null)
FAILS=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

if /bin/ping -c1 -W $TIMEOUT "$PRIMARY_IP" > /dev/null 2>&1; then
    if [ "$FAILS" -gt 0 ]; then
        log "Primary answered after $FAILS failed check(s)."
    fi
    echo 0 > "$STATE_FILE"
    if [ "$CURRENT" = "true" ]; then
        log "Primary is up. Disabling DHCP on backup..."
        /usr/bin/pihole-FTL --config dhcp.active false > /dev/null
    fi
else
    FAILS=$((FAILS + 1))
    echo "$FAILS" > "$STATE_FILE"
    log "Primary ping failed ($FAILS/$FAIL_THRESHOLD)."
    if [ "$CURRENT" = "false" ] && [ "$FAILS" -ge "$FAIL_THRESHOLD" ]; then
        log "Primary is down. Enabling DHCP on backup..."
        /usr/bin/pihole-FTL --config dhcp.active true > /dev/null
    fi
fi

if [ -d "${METRIC%/*}" ]; then
    ACTIVE=$(/usr/bin/pihole-FTL --config dhcp.active 2>/dev/null)
    echo "pihole_failover_dhcp_active $([ "$ACTIVE" = "true" ] && echo 1 || echo 0)" > "$METRIC.tmp" && mv "$METRIC.tmp" "$METRIC"
fi
