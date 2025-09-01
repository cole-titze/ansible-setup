# ansible-setup
This is the main repo for running ansible scripts for my homelab
## Installing required roles
```
ansible-galaxy install -r requirements.yml --roles-path roles/ --force
```
## Running playbooks
```
ansible-playbook -i inventories/inventory.ini playbooks/raspberry-pi-setup.yml
```
## Make scripts executable
```
chmod +x ~/source/repos/ansible-setup/raspberry-pi-playbooks/utilities/scripts/Upgrade.sh
chmod +x ~/source/repos/ansible-setup/raspberry-pi-playbooks/utilities/scripts/Deploy.sh
chmod +x ~/source/repos/ansible-setup/raspberry-pi-playbooks/utilities/scripts/Uninstall.sh
chmod +x ~/source/repos/ansible-setup/mac-playbooks/backup/scripts/Backup.sh
```