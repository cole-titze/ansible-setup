# ansible-setup

Main orchestration repo for my homelab Ansible playbooks.

## Prerequisites

- Ansible installed on your control machine
- SSH keys configured for each host (see `inventories/inventory.ini`)

## Installing required roles

```bash
ansible-galaxy install -r requirements.yml --roles-path roles/ --force
```

## Running playbooks

All playbooks use the same inventory:

```bash
ansible-playbook -i inventories/inventory.ini <playbook>
```

### Raspberry Pi setup

```bash
# Setup all Raspberry Pis (OS config, updates, timezone, nightly updates, Pi-hole update)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/setup/raspberry-pi-setup.yml

# Setup backup Pi (Unbound, Pi-hole DHCP failover)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/setup/raspberry-pi-backup.yml
```

### Docker machine (dockerpi)

Requires secrets in `~/source/ansible-files/vars/cluster_vars.yml`.

```bash
# Install Docker + deploy active containers (Portainer, NHL Odds, Unbound)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/docker-machine/docker-setup.yml
```

### Kubernetes cluster

```bash
# Full cluster setup (K3s, Helm, Longhorn, all services)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml

# Deploy a specific service with tags
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml -t traefik

# Reset the cluster
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/reset-kubernetes.yml

# Uninstall K3s
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/uninstall-kubernetes.yml
```

### Utilities

```bash
# Upgrade all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/upgrade.yml

# Shutdown all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/shutdown.yml
```

Helper scripts (need `chmod +x` first):
- `raspberry-pi-playbooks/utilities/scripts/Deploy.sh`
- `raspberry-pi-playbooks/utilities/scripts/Upgrade.sh`
- `raspberry-pi-playbooks/utilities/scripts/Uninstall.sh`

### Mac backups

```bash
ansible-playbook mac-playbooks/backup/backup.yml
```
