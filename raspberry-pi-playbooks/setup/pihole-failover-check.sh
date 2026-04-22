#!/bin/bash

PRIMARY_IP="10.42.0.2"
TIMEOUT=2

CURRENT=$(/usr/bin/pihole-FTL --config dhcp.active 2>/dev/null)

if /bin/ping -c1 -W $TIMEOUT "$PRIMARY_IP" > /dev/null 2>&1; then
    if [ "$CURRENT" = "true" ]; then
        echo "Primary is up. Disabling DHCP on backup..."
        /usr/bin/pihole-FTL --config dhcp.active false
    fi
else
    if [ "$CURRENT" = "false" ]; then
        echo "Primary is down. Enabling DHCP on backup..."
        /usr/bin/pihole-FTL --config dhcp.active true
    fi
fi
