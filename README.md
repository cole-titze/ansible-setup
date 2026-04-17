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
# Setup all Raspberry Pis (OS config, updates, timezone, nightly updates, Pi-hole update)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/setup/raspberry-pi-setup.yml

# Setup backup Pi (Unbound, Pi-hole DHCP failover)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/setup/raspberry-pi-backup.yml
```

### Docker machine (dockerpi)

Requires secrets in `~/source/ansible-files/vars/cluster_vars.yml` and `nhl_vars.yml`.

```bash
# Install Docker + deploy active containers (Portainer, NHL Odds, Unbound)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/docker-machine/docker-setup.yml

# Skip the NHL Odds container
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/docker-machine/docker-setup.yml --skip-tags nhl-odds

# Uninstall the Docker NHL Odds container and cron jobs
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/docker-machine/uninstall-nhl-odds.yml
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

#### NHL Odds

Requires the following secrets in `~/source/ansible-files/vars/nhl_vars.yml`:

| Variable | Description |
|----------|-------------|
| `nhl_odds_postgres_password` | PostgreSQL password |
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

A nightly CronJob (`nhl-odds-db-backup`) also runs at 1am CT inside the cluster, keeping 7 days of backups on a dedicated PVC.

### Utilities

```bash
# Upgrade all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/upgrade.yml

# Shutdown all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/shutdown.yml
```

Helper scripts (need `chmod +x` first):
- `raspberry-pi-playbooks/utilities/scripts/Deploy.sh` — full cluster deploy
- `raspberry-pi-playbooks/utilities/scripts/Upgrade.sh` — upgrade all Pis
- `raspberry-pi-playbooks/utilities/scripts/Uninstall.sh` — uninstall K3s cluster

### Mac backups

```bash
ansible-playbook mac-playbooks/backup/backup.yml
```
