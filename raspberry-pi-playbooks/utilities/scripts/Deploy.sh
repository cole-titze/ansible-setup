#!/bin/bash
# Assumes running from root directory of repo (ansible-setup)
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml