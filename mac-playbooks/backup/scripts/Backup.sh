#!/bin/bash
# Assumes running from root directory of repo (ansible-setup)
ansible-playbook -i inventories/inventory.ini mac-playbooks/backup/backup.yml