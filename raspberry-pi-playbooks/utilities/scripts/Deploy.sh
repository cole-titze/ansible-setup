#!/bin/bash
# Assumes running from root directory of repo (ansible-setup)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml