#!/bin/bash
# Nightly apt upgrade for K3s nodes.
# Workers never reboot themselves: kured (cluster/kubernetes/kured) watches /var/run/reboot-required
# and reboots them one at a time with a drain. node01 runs no kured pod (control-plane taints) and
# has no workloads to drain, so it passes --reboot and reboots itself when needed.
# full-upgrade (not upgrade) so new kernel/firmware packages that pull in new dependencies
# (linux-image-rpi-*, rpi-eeprom) are installed instead of kept back.
set -e
# root's cron PATH is /usr/bin:/bin, which has no reboot (it lives in /usr/sbin)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get full-upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
if [ -f /var/run/reboot-required ]; then
    if [ "$1" = "--reboot" ]; then
        echo "Reboot required, rebooting..."
        reboot
    else
        echo "Reboot required, leaving it to kured"
    fi
else
    echo "No reboot required, skipping reboot"
fi
