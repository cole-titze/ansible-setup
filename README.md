# ansible-setup

Main orchestration repo for my homelab Ansible playbooks.

## Prerequisites

- Ansible installed on your control machine
- SSH keys configured for each host (see `inventories/inventory.ini`)
- On macOS, add to your shell profile to prevent Python fork crashes:
  ```bash
  export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
  ```

## Installing required roles and collections

```bash
ansible-galaxy install -r requirements.yml --roles-path roles/ --force
ansible-galaxy collection install community.crypto kubernetes.core
```

## Running playbooks

All playbooks use the same inventory:

```bash
ansible-playbook -i inventories/inventory.ini <playbook>
```

### Raspberry Pi setup

```bash
# Setup all Raspberry Pis (OS config, updates, timezone, Pi-hole update)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/setup/raspberry-pi-setup.yml

# Setup backup Pi (Unbound, Pi-hole DHCP failover) — also applies staggered maintenance
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/setup/raspberry-pi-backup.yml
```

> **Note:** `raspberry-pi-setup.yml` does not wire in the staggered maintenance crons. After running it on dockerpi or cluster nodes, run the appropriate maintenance playbook below.

### Nightly maintenance

Each Pi updates and conditionally reboots on its own schedule so the fleet never goes down simultaneously.

| Host | Time (CT) | Playbook |
|------|-----------|----------|
| dockerpi_backup | 1:00am | `backup-node-maintenance.yml` |
| dockerpi | 1:45am | `docker-node-maintenance.yml` |
| node02 | 2:00am | `k8s-node-maintenance.yml` |
| node03 | 2:45am | `k8s-node-maintenance.yml` |
| node01 | 3:30am | `k8s-node-maintenance.yml` |

Cluster nodes only reboot if packages require it (`/var/run/reboot-required`). Docker nodes always reboot. Node order ensures workers go before the control plane, and the Longhorn storage node (node03) goes before node01.

```bash
# Apply staggered maintenance to Docker machine
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/docker-node-maintenance.yml

# Apply staggered maintenance to backup Pi
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/backup-node-maintenance.yml

# Apply staggered maintenance to K3s cluster nodes
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml -t node-maintenance
```

**Logs** (rotated weekly, 4 weeks retained):

| Log | Host |
|-----|------|
| `/var/log/node-update.log` | all Pis |
| `/var/log/k8s-node-update.log` | node01–03 |
| `/var/log/portainer-update.log` | dockerpi |
| `/var/log/home-assistant-update.log` | dockerpi |
| `/var/log/home-assistant-backup.log` | dockerpi |
| `/var/log/pihole-update.log` | dockerpi, dockerpi_backup |
| `/var/log/pihole-failover.log` | dockerpi_backup |

### Docker machine (dockerpi)

Requires secrets in `~/source/ansible-files/vars/cluster_vars.yml` and `nhl_vars.yml`.

```bash
# Install Docker + deploy active containers (Portainer, Home Assistant, Unbound, Pi-hole)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/docker-machine/docker-setup.yml
```

### Kubernetes cluster

#### Cluster services

Access via any worker node IP (`10.42.0.21` or `10.42.0.22`):

| Service | URL | Notes |
|---------|-----|-------|
| Portainer | `https://10.42.0.21:30779` | K8s management UI |
| Grafana | `http://10.42.0.21:30300` | Cluster monitoring |
| Longhorn | `http://10.42.0.21:30880` | Storage management |
| Esphome | `http://10.42.0.21:30605` | ESP device management |
| Magic Mirror | `http://10.42.0.21:30808` | Smart mirror UI |
| Traefik | `http://10.42.0.21:31498` | Ingress dashboard |
| NHL Odds | `https://odds.nhlwager.com` | External (Cloudflare tunnel) |

**Not currently deployed (commented out in playbook):** NFS Provisioner, Codespace, Folding at Home, Minecraft, Monero Miner, Dashboard, Nextcloud, Pi-hole

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

#### NHL Odds

Deployed on Kubernetes in the `nhl-odds` namespace. Requires the following secrets in `~/source/ansible-files/vars/nhl_vars.yml`:

| Variable | Description |
|----------|-------------|
| `nhl_odds_postgres_password` | PostgreSQL password (CNPG) |
| `nhl_odds_api_key` | odds-api.com API key |
| `nhl_odds_api_backfill_key` | Backfill API key |
| `nhl_odds_cloudflare_tunnel_token` | Cloudflare tunnel token for external access |

**Backup/restore:**

Pull a backup from the cluster to your Mac:
```bash
ansible-playbook -i inventories/inventory.ini mac-playbooks/backup/backup.yml -t nhl-odds
```
This saves to `~/source/ansible-files/backups/nhl-odds/nhl.dump`.

To restore on next deploy, ensure that file exists — the deploy playbook checks for it automatically and restores it after the pods start.

A nightly CronJob (`nhl-odds-db-backup`) also runs at 1am CT inside the cluster, keeping 7 days of backups on each worker node at `/home/pi/backups/nhl-odds/`.

### Utilities

```bash
# Shutdown all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/shutdown.yml
```

Helper scripts (need `chmod +x` first):
- `raspberry-pi-playbooks/utilities/scripts/Deploy.sh` — full cluster deploy
- `raspberry-pi-playbooks/utilities/scripts/Uninstall.sh` — uninstall K3s cluster

### Mac backups

```bash
ansible-playbook mac-playbooks/backup/backup.yml
```
