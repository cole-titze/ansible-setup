#!/bin/bash
# Nightly apt upgrade for K3s nodes.
# Workers never reboot themselves: kured (cluster/kubernetes/kured) watches /var/run/reboot-required
# and reboots them one at a time with a drain. node01 runs no kured pod (control-plane taints) and
# has no workloads to drain, so it passes --reboot and reboots itself when needed.
set -e
apt-get update -y
apt-get upgrade -y
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
