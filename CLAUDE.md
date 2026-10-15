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
```

Helper scripts (need `chmod +x`): `raspberry-pi-playbooks/utilities/scripts/Deploy.sh`, `Upgrade.sh`, `Uninstall.sh`.

## Inventory

Defined in `inventories/inventory.ini`. Group variables in `inventories/group_vars/`.

| Group | Host | IP | Purpose |
|-------|------|----|---------|
| `backup_raspberrypi` | `dockerpi_backup` | .3 | Backup Pi (Unbound, Pi-hole failover, off-cluster nhl-odds dumps) |
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

Currently active K8s services (tags in `raspberry-pi-cluster.yml`): `helm`, `traefik`, `longhorn`, `portainer`, `magic-mirror`, `prometheus` (metrics API comes from K3s's built-in metrics-server), `nhl-odds`, `kured` (drained one-at-a-time worker reboots, 2:00-2:55 CT).

Traefik runs as a DaemonSet and handles TLS for `.kubecluster` local domains using `IngressRoute` CRDs (`traefik.io/v1alpha1`). It generates a self-signed wildcard cert for `*.kubecluster` using the `community.crypto` collection.

### Primary DNS (node04)

node04 (10.42.0.2, formerly dockerpi) is a K3s worker that also runs the primary Pi-hole + unbound on the host, outside Kubernetes. It keeps IP .2 because DHCP hands it out as the primary DNS; `dockerpi_backup` (.3) is the standalone secondary and takes over DHCP when .2 stops answering pings. Its K3s agent uses `/etc/k3s-resolv.conf` (`k3s_resolv_conf` host var) because the host resolver is 127.0.0.1, which K3s rejects.

### Off-cluster DB copies

`utilities/backup-node-db-pull.yml` (also imported by `setup/raspberry-pi-backup.yml`): `dockerpi_backup` pulls the day's nhl-odds dump from the first worker that has it at 4:00 into `/home/pi/backups/nhl-odds` (keeps 30; log `/var/log/nhl-backup-pull.log`). Its key is limited on workers to read-only `rrsync` of that dir.
