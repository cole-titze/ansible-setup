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

