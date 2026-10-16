#!/bin/bash
# Nightly apt upgrade for the backup Pi. Reboots only when a package asks for it
# (/var/run/reboot-required, written by /etc/kernel/postinst.d/unattended-upgrades),
# so the secondary DNS isn't bounced every night.
# full-upgrade (not upgrade) so new kernel/firmware packages that pull in new dependencies
# (linux-image-rpi-*, rpi-eeprom) are installed instead of kept back.
set -e
# root's cron PATH is /usr/bin:/bin, which has no reboot (it lives in /usr/sbin)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
echo "$(date '+%Y-%m-%d %H:%M:%S') Starting nightly update"
apt-get update -y
apt-get full-upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
if [ -f /var/run/reboot-required ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Reboot required, rebooting..."
    reboot
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') No reboot required, skipping reboot"
fi
