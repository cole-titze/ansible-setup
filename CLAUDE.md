# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal homelab Ansible orchestration for a Raspberry Pi cluster on `10.42.0.0/24`. Covers OS setup, a K3s cluster, and macOS backups. No test suite or CI pipeline.

## Common Commands

All commands run from this directory (`ansible-setup/`).

```bash
# Install/update external roles
ansible-galaxy install -r requirements.yml --roles-path roles/ --force

# Install required Ansible collections (one-time setup)
ansible-galaxy collection install community.crypto kubernetes.core

# Run a playbook
ansible-playbook -i inventories/inventory.ini <playbook.yml>

# Dry-run
ansible-playbook -i inventories/inventory.ini <playbook.yml> --check

# Deploy a single Kubernetes service by tag
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml -t traefik

# Verbose debugging
ansible-playbook -i inventories/inventory.ini <playbook.yml> -vvv
```

### Key playbooks

```bash
# OS setup for all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/setup/raspberry-pi-setup.yml

# Full K3s cluster (K3s, Helm, Longhorn, all services)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml

# Reset / uninstall cluster
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/reset-kubernetes.yml
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/uninstall-kubernetes.yml

# Upgrade all Pis
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/utilities/upgrade.yml

# Mac backups (no inventory flag needed)
ansible-playbook mac-playbooks/backup/backup.yml

# Install/refresh the Mac's launchd jobs (nightly backup 4:30, stale-backup check 9:00,
# restore drill Sat 5:30; reports go to Discord)
ansible-playbook mac-playbooks/scheduled-jobs/scheduled-jobs.yml
```

Helper scripts (need `chmod +x`): `raspberry-pi-playbooks/utilities/scripts/Deploy.sh`, `Upgrade.sh`, `Uninstall.sh`.

## The Mac

No automatic agents (headless Claude, Remote Control) run on the MacBook, and nothing on the backup Pi can run anything on it (Remote Login off, no Pi → Mac paths); it holds sensitive data. Its launchd jobs only back up: the nightly copy (which the Mac starts, pulling from the Pi), and until #24 wraps up, the iCloud stale check and restore drill. New automation goes on the backup Pi.

## Inventory

Defined in `inventories/inventory.ini`. Group variables in `inventories/group_vars/`.

| Group | Host | IP | Purpose |
|-------|------|----|---------|
| `backup_raspberrypi` | `dockerpi_backup` | .3 | Backup Pi (Unbound, Pi-hole failover, off-cluster nhl-odds + Grafana backups, backup stale check + restore drill) |
| `control_plane` | `node01` | .20 | K3s master |
| `nodes` | `node02–04` | .21–.22, .2 | K3s workers (node04 = old dockerpi, also primary Pi-hole on the host) |
| `storage` | `node03` | .22 | Longhorn storage |
| `pikvms` | `pikvm` | pikvm | KVM management (user: root, python3.14) |

All Pi hosts use SSH key auth (`~/.ssh/<hostname>`) and `python3.11`.

## Architecture

### External roles (requirements.yml → roles/)

- `raspberry-pi` — Pi OS setup
- `docker` — Docker installation and container management (separate repo: `ansible-role-docker`)
- `nfs` — NFS setup
- `wol` — Wake-on-LAN

### Kubernetes manifests pattern

Each K8s service under `raspberry-pi-playbooks/cluster/kubernetes/<service>/` follows this pattern:
- `<service>-template.yml` — raw Jinja2 manifest template (e.g., `{{ nhl_odds_postgres_password }}`), rendered at deploy time via `lookup('template', ...)`
- `<service>.yml` — the Ansible playbook that applies the template

Templates are **never pre-rendered and committed**; Ansible renders them in-memory at runtime. All K8s playbooks run against `control_plane` and set `K8S_AUTH_KUBECONFIG: /etc/rancher/k3s/k3s.yaml` in their environment.

Secrets and cluster variables come from `~/source/ansible-files/vars/cluster_vars.yml` (external, not in repo).

Currently active K8s services (tags in `raspberry-pi-cluster.yml`): `helm`, `traefik`, `longhorn`, `magic-mirror`, `prometheus` (metrics API comes from K3s's built-in metrics-server), `loki` (Loki + Alloy: pod logs and node journals, 14 days, in Grafana Explore), `nhl-odds` (also runs a three-node Elasticsearch for site search, one pod per worker with a replica of every shard, rebuilt hourly from Postgres, and Ollama with a small CPU embedding model for semantic article search, as two copies so the search-index job's batches never delay search queries: `nhl-odds-embeddings` for the job, `nhl-odds-embeddings-query` for the webapi), `kured` (drained one-at-a-time worker reboots, 2:00-2:55 CT).

Traefik runs as a DaemonSet and handles TLS for `.kubecluster` local domains using `IngressRoute` CRDs (`traefik.io/v1alpha1`). It generates a self-signed wildcard cert for `*.kubecluster` using the `community.crypto` collection.

### Primary DNS (node04)

node04 (10.42.0.2, formerly dockerpi) is a K3s worker that also runs the primary Pi-hole + unbound on the host, outside Kubernetes. It keeps IP .2 because DHCP hands it out as the primary DNS; `dockerpi_backup` (.3) is the standalone secondary and takes over DHCP after .2 misses 3 pings in a row (one check per minute, `setup/pihole-failover-check.sh`, timestamped log `/var/log/pihole-failover.log`). Its K3s agent uses `/etc/k3s-resolv.conf` (`k3s_resolv_conf` host var) because the host resolver is 127.0.0.1, which K3s rejects.

`utilities/dns-pi-hardening.yml` hardens both Pi-hole Pis: root SSH off, avahi masked, web UI HTTPS-only (4430), and an nftables table `inet dnspi` loaded by `dnspi-firewall.service` (never `nftables.service`, whose flush would wipe K3s rules on node04). Backup Pi is default-drop (DNS/NTP/UI/SSH from LAN + WireGuard 10.6.0.0/24, DHCP from anywhere for failover, 9633 from cluster); node04 is default-accept with only rpcbind 111 limited to cluster nodes/pods. Firewall changes load behind a 5-minute auto-rollback timer.

### Off-cluster DB copies

`utilities/backup-node-db-pull.yml` (also imported by `setup/raspberry-pi-backup.yml`): at 4:00 `dockerpi_backup` pulls the day's nhl-odds dump from the first worker that has it into `/home/pi/backups/nhl-odds` (keeps 30) and the Grafana DBs from every worker into `/home/pi/backups/grafana` (keeps 35), and writes a `SHA256SUMS` in each (log `/var/log/nhl-backup-pull.log`). Its key is limited on workers to read-only `rrsync` of `/home/pi/backups`.

The pull also copies pi's Claude memory, settings and `~pi/claude-work` into `/home/pi/backups/claude/`; the Mac stores them in iCloud as `backups/backup-pi-claude/backup_<date>` (30 days, `mac-playbooks/backup/offsite/claude-backup.yml`) and never loads them.

The Mac's nightly backup (4:30) copies those folders into iCloud through a non-iCloud staging dir, checks the new iCloud copies against `SHA256SUMS`, then runs `mark-copied` on the Pi. Its key (`~/.ssh/backuppi_offsite`) is limited on the Pi to read-only `rrsync` of `/home/pi/backups` plus `mark-copied` (`homelab-offsite-access`), which writes `/var/lib/homelab/mac-last-copied`.

`utilities/backup-node-jobs.yml`: the backup Pi's systemd timers (moving the Mac's launchd jobs there, #24). `homelab-backup-stale-check` (9:00) posts to Discord if the newest dump or Grafana DB on the Pi is over 26h old, or the Mac's copy is over 48h old. `homelab-restore-drill` (Sat 5:00) restores the newest dump into a throwaway PostgreSQL 18 (PGDG packages, server disabled, socket-only scratch cluster in `/var/tmp/restore-drill`) and checks the newest Grafana DB. Scripts in `utilities/files/homelab/`, logs in `/var/log/homelab/`, Discord webhook in root-only `/etc/homelab/discord-webhook` (from `alerting_vars.yml`; re-run the playbook after changing it). Run one now: `sudo systemctl start homelab-<job>.service`.

`utilities/backup-node-alert-agent.yml`: the alert agent (moved from the Mac). `homelab-alert-agent.timer` runs every minute as root: asks Alertmanager for new alerts sent to Discord and runs headless Claude Code as `pi` (dontAsk, tool allowlist in the script; nodes only through `homelab-node`'s command allowlist) with `alert-agent-prompt.md`, then posts the report to Discord. Claude login: a `claude setup-token` token in root-only `/etc/homelab/claude-oauth-token`; the timer is only enabled once it exists. State in `/var/lib/homelab/alert-agent`, logs `/var/log/homelab/alert-agent-*`, reports `~pi/alert-agent/`. Next steps go to `~pi/backups/alert-agent/next-steps.txt` and the Discord report; nothing from the Pi is fed into the Mac. New alerts wait while the weekly upgrade runs.

`utilities/backup-node-remote-control.yml`: Claude Code Remote Control on the backup Pi (`claude-rc.service`, session **backup-pi**, as `pi` in `~pi/source/repos/ansible-setup`, settings `/etc/homelab-claude-rc-settings.json` from `utilities/files/homelab/claude-rc-settings.json`). The Pi has Ansible (Debian's package), the roles, the vaulted vars in `~pi/source/ansible-files/vars` and the vault password in `~pi/.config/homelab/vault-pass` (copied from the Mac by the playbook; re-run it after changing vars). The inventory's `~/.ssh/<host>` key names are symlinks to pi's `homelab_nodes` key.

`utilities/backup-node-weekly-upgrade.yml`: the weekly upgrade (moved from the Mac). `homelab-weekly-upgrade.timer` (Sat 10:00, after the Sat 5:00 restore drill) runs headless Claude Code as `pi` (bypassPermissions) with `weekly-upgrade-prompt.md`: Saturday job checks + uptime blips (`~pi/homelab/uptime-blips.csv`), `/k8s-major-upgrade`, and the nhl-odds security pass. App changes go through PRs and CI (no .NET/Node on the Pi); `/update-mac` is run by hand on the Mac. `gh` is logged in as `pi` (`gh auth login --web --scopes workflow`, `gh auth setup-git`); repos in `~pi/source/repos`, skills linked from `claude-skills` into `~pi/.claude/skills`. Log `/var/log/homelab/weekly-upgrade-*`.

`utilities/backup-node-docker.yml`: rootless Docker for `pi` (daemon runs as pi via `systemctl --user`, context `rootless`; the root daemon is masked, `pi` is not in the `docker` group, host firewall untouched). For test copies of the apps (docker compose, local e2e, k6) before changes reach the cluster; publish ports on `127.0.0.1`.

The backup Pi's full setup is `setup/raspberry-pi-backup.yml` (imports every `backup-node-*.yml`). By hand after a wipe: `claude auth login` and the `claude setup-token` token (alert agent, weekly upgrade), `gh auth login`, and the vault password on the Mac for the first run.

## On the backup Pi (Remote Control session)

When running on `dockerpibackup` as `pi`:
- Run playbooks with `homelab-run <playbook.yml> [-t <tag>] [--check --diff]`, not `ansible-playbook` directly: it takes a lock so two runs never overlap and logs to `/var/log/homelab/runs/`. Dry-run first (`--check --diff`, allowed without asking), then the real run.
- The checkout follows GitHub `main`: `git pull --ff-only` before deploying. Changes made on the Mac must be pushed first.
- Status: `systemctl list-timers 'homelab-*'`; job logs in `/var/log/homelab/` (`backup-stale-check-*`, `restore-drill-*`, `alert-agent-*`, `runs/`); the Mac's last iCloud copy is the epoch in `/var/lib/homelab/mac-last-copied`; backups in `~/backups/` (`nhl-odds/`, `grafana/`, `alert-agent/next-steps.txt`); the nightly pull log is `/var/log/nhl-backup-pull.log`.
- `utilities/dns-pi-hardening.yml` changes this Pi's own firewall: it keeps its 5-minute auto-rollback timer, so confirm within 5 minutes or the change reverts.
