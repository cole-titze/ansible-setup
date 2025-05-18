#!/bin/bash

PRIMARY_IP="10.0.0.61"
TIMEOUT=2

if ping -c1 -W $TIMEOUT "$PRIMARY_IP" > /dev/null; then
    echo "Primary is up. Disabling DHCP on backup..."
    pihole -a disable-dhcp
else
    echo "Primary is down. Enabling DHCP on backup..."
    pihole -a enable-dhcp
fi