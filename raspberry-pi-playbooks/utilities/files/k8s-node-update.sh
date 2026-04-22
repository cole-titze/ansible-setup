#!/bin/bash
set -e
apt-get update -y
apt-get upgrade -y
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required, rebooting..."
    reboot
else
    echo "No reboot required, skipping reboot"
fi
