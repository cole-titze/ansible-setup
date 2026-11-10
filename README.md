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

> **Note:** `raspberry-pi-setup.yml` does not wire in the staggered maintenance crons. After running it on cluster nodes, run the appropriate maintenance playbook below.

### Nightly maintenance

Each Pi updates and conditionally reboots on its own schedule so the fleet never goes down simultaneously.

| Host | Time (CT) | Playbook |
|------|-----------|----------|
| dockerpi_backup | 1:00am | `backup-node-maintenance.yml` |
| node04 | 1:45am | `k8s-node-maintenance.yml` |
| node02 | 2:00am | `k8s-node-maintenance.yml` |
| node03 | 2:45am | `k8s-node-maintenance.yml` |
| node01 | 3:30am | `k8s-node-maintenance.yml` |

Every Pi only reboots if packages require it (`/var/run/reboot-required`): the backup Pi reboots itself, and on the cluster kured drains and reboots workers one at a time. Node order ensures workers go before the control plane, and the Longhorn storage node (node03) goes before node01.

```bash
# Apply staggered maintenance to backup Pi
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/backup-node-maintenance.yml

# Apply staggered maintenance to K3s cluster nodes
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml -t node-maintenance

# Nightly PiKVM update (systemd timer; reboots only when an update needs it)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/pikvm-maintenance.yml
```

**Logs** (rotated weekly, 4 weeks retained):

| Log | Host |
|-----|------|
| `/var/log/node-update.log` | all Pis |
| `/var/log/k8s-node-update.log` | node01–04 |
| `/var/log/pihole-update.log` | node04, dockerpi_backup |
| `/var/log/pihole-failover.log` | dockerpi_backup |
| `/var/lib/kvmd/pst/data/pikvm-update.log` | pikvm (last 2000 lines kept; `/var/log` is tmpfs there) |

### Primary DNS (node04)

node04 (the old dockerpi, 10.42.0.2) is a K3s worker that also runs the primary Pi-hole + unbound directly on the host, outside Kubernetes. Its K3s agent uses `/etc/k3s-resolv.conf` (set via `k3s_resolv_conf` in its host_vars) because the host resolver is loopback.

```bash
# Flush Pi-hole + unbound caches on both DNS Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/clear-pihole-cache.yml
```

### Kubernetes cluster

Adding a worker or control-plane Pi (flash, SSH key, inventory, playbooks): see [Adding cluster nodes](https://github.com/cole-titze/nhl-odds/wiki/Adding-Cluster-Nodes).

#### Cluster services

Access via any worker node IP (`10.42.0.21` or `10.42.0.22`):

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | `http://10.42.0.21:30300` | Cluster monitoring |
| Longhorn | `https://longhorn.kubecluster` | Storage management (login: Passwords app, `longhorn.kubecluster`) |
| Esphome | `http://10.42.0.21:30605` | ESP device management |
| Magic Mirror | `http://10.42.0.21:30808` | Smart mirror UI |
| Traefik | `https://traefik.kubecluster/dashboard/` | Ingress dashboard (same login as Longhorn) |
| NHL Odds | `https://nhl.half-built.com` | External (Cloudflare tunnel) |

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

#### Optional services

These are defined in the playbook but tagged `never` so they don't run by default. Deploy them explicitly with their tag:

```bash
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml -t <tag>
```

| Tag | Service | Notes |
|-----|---------|-------|
| `qrl-miner` | QRL Miner | Requires `qrl_wallet_address` in `cluster_vars.yml` |
| `monero-miner` | Monero Miner | Requires `monero_wallet_address` in `cluster_vars.yml` |
| `minecraft` | Minecraft Server | |
| `nextcloud` | Nextcloud | |
| `pi-hole` | Pi-hole | Currently runs on dockerpi_backup instead |
| `dashboard` | Kubernetes Dashboard | Superseded by Prometheus/Grafana |
| `nfs` | NFS Provisioner | Superseded by Longhorn |
| `codespace` | Codespace | |
| `folding-at-home` | Folding@Home | |

#### NHL Odds

Deployed on Kubernetes in the `nhl-odds` namespace. Requires the following secrets in `~/source/ansible-files/vars/nhl_vars.yml`:

| Variable | Description |
|----------|-------------|
| `nhl_odds_postgres_password` | PostgreSQL password (CNPG) |
| `nhl_odds_api_key` | odds-api.com API key |
| `nhl_odds_api_backfill_key` | Backfill API key |
| `nhl_odds_cloudflare_tunnel_token` | Cloudflare tunnel token for external access |
| `nhl_odds_admin_api_key` | Key required in the `X-Admin-Key` header by every webapi `/api/Admin` endpoint; enter it on the site's `/admin` page to unlock it (e.g. `openssl rand -hex 32`) |

**Backup/restore:**

Pull a backup from the cluster to your Mac:
```bash
ansible-playbook -i inventories/inventory.ini mac-playbooks/backup/backup.yml -t nhl-odds
```
This saves to `~/source/ansible-files/backups/nhl-odds/nhl.dump`.

To restore on next deploy, ensure that file exists — the deploy playbook checks for it automatically and restores it after the pods start.

A nightly CronJob (`nhl-odds-db-backup`) also runs at 1am CT inside the cluster, keeping 7 days of backups on each worker node at `/home/pi/backups/nhl-odds/`.

**Site search (Elasticsearch):**

A three-node Elasticsearch (`nhl-odds-elasticsearch`, StatefulSet, one pod per worker by required anti-affinity, each 1 GB heap, 1.5Gi request, 2Gi limit) serves the site's search. All three are master-eligible, so any two keep a quorum, and nhl-odds creates its indices with `auto_expand_replicas: 0-1`, so every shard has a copy on a second node: search survives one node down (a kured reboot or a dead Pi; the PDB allows one at a time, and the drained node's pod waits Pending until it's back). Node-to-node traffic is TLS with a CA and a shared node cert the playbook makes once into `nhl-odds-elasticsearch-transport-certs` (delete it and re-run to rotate). The first run after the single-node version deletes that StatefulSet and its volume (a StatefulSet's `serviceName` can't change), so search is empty until the playbook's index build finishes. The `nhl-odds-entry-search-index` CronJob (`RUN_MODE=SearchIndex`, hourly at :20 CT) rebuilds its indices from Postgres, swapping each in when complete, so it needs no backup: if its volume is lost, search is empty until the next run. No new vars: the playbook creates random passwords once in cluster secrets (`nhl-odds-elasticsearch-credentials` for the `elastic` superuser, used only by the playbook and probes; `nhl-odds-search-writer-credentials` for the CronJob; `nhl-odds-search-reader-credentials` for the read-only webapi) and sets up the users. To look at it: `kubectl exec -it -n nhl-odds nhl-odds-elasticsearch-0 -- sh -c 'curl -u "elastic:$ELASTIC_PASSWORD" localhost:9200/_cat/indices?v'`.

**Semantic article search (embeddings):**

`nhl-odds-embeddings` runs Ollama on the CPU with one small embedding model (`nhl_odds_embedding_model` in `nhl-odds.yml`, pinned to `nomic-embed-text:v1.5` so a pod restart can't pull different weights, ~300 MB, 1.5Gi limit; new versions are the k8s-major-upgrade skill's call). An init container pulls the model onto its 2Gi volume on first start. The search-index CronJob gives each new or changed article a vector (unchanged ones reuse the live index's, which is why `nhl_search_writer` also has `read`), and the webapi embeds each search to find articles by meaning as well as by keyword. If it's down, articles are indexed and searched by keyword only, never an error. The first run after deploying embeds every article, newest first, 30 minutes per run, so it can take a few hourly runs to catch up. To check it: `kubectl logs -n nhl-odds job/<latest search-index job> | grep "Article vectors"`.

### Utilities

```bash
# Shutdown all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/shutdown.yml
```

Helper scripts (need `chmod +x` first):
- `raspberry-pi-playbooks/utilities/scripts/Deploy.sh` — full cluster deploy
- `raspberry-pi-playbooks/utilities/scripts/Uninstall.sh` — uninstall K3s cluster

### New Mac setup

Follow [`mac-playbooks/macbook-setup.md`](mac-playbooks/macbook-setup.md). Its **Start here** section installs Claude Code, which then works through the rest of the runbook.

### Mac backups

```bash
ansible-playbook mac-playbooks/backup/backup.yml
```

The nightly backup (launchd, 4:30) copies the backup Pi's nhl-odds dumps and Grafana DBs into iCloud and backs up the Mac's `~/.ssh`, `~/.kube` and `~/.claude`. Launchd jobs only run while someone is logged in: after a reboot, nothing runs until you log in. The backup Pi's 9:00 stale check posts to Discord if the Mac hasn't copied for 2 days.

### Backup Pi jobs and Remote Control

The backup Pi (`dockerpi_backup`) runs the homelab's scheduled jobs and a Claude Code Remote Control session, so day-to-day running doesn't need the Mac:

```bash
# Backup stale check (9:00), restore drill (Sat 5:00), the Mac's offsite-copy key
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/backup-node-jobs.yml
# Alert agent (every minute)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/backup-node-alert-agent.yml
# Remote Control (claude-rc.service)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/backup-node-remote-control.yml
# Weekly upgrade (Sun 10:00; needs gh logged in as pi first)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/backup-node-weekly-upgrade.yml
```

Re-run the jobs and Remote Control playbooks after changing the vars in `~/source/ansible-files/vars`: they copy the Discord webhook, the vaulted vars and the vault password to the Pi.

Three logins, all done once by hand as `pi` on the Pi (`ssh -i ~/.ssh/dockerpibackup pi@10.42.0.3`):

1. **Alert agent:** `claude setup-token` (a one-year, inference-only token). Put the token in `/etc/homelab/claude-oauth-token` (root, 0600), then re-run the alert agent playbook to start its timer.
2. **Remote Control:** `claude auth login` (Remote Control needs a full login; use a claude.ai account with two-factor login on, since it can drive the homelab). Run `claude` once in `~/source/repos/ansible-setup` to accept the folder trust prompt (it defaults to "No, exit"), and `claude remote-control` once to answer its "Enable Remote Control?" prompt (y), then re-run the Remote Control playbook to start `claude-rc.service`.

3. **GitHub (weekly upgrade):** `gh auth login --hostname github.com --git-protocol https --web --scopes workflow`, then `gh auth setup-git`.

Then open the Claude app (or claude.ai/code): the session is named **backup-pi**. Every command that isn't on the allow list in `utilities/files/homelab/claude-rc-settings.json` asks for approval in the app; resets, uninstalls, `kubectl delete` and the secrets are denied. Playbooks run through `homelab-run <playbook> [options]`, one at a time, logged to `/var/log/homelab/runs/`.

The Pi's checkout follows GitHub, so push changes made on the Mac before running them from the Pi (`git pull --ff-only` in the session).
