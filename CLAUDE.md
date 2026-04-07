# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal homelab Ansible orchestration for a Raspberry Pi cluster on `10.42.0.0/24`. Covers OS setup, a Docker host, a K3s cluster, and macOS backups. No test suite or CI pipeline.

## Common Commands

All commands run from this directory (`ansible-setup/`).

```bash
# Install/update external roles
ansible-galaxy install -r requirements.yml --roles-path roles/ --force

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

# Docker host (Portainer, NHL Odds, Unbound) — requires secrets file
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/docker-machine/docker-setup.yml

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
| `docker` | `dockerpi` | .61 | Primary Docker/Home Assistant server |
| `backup_raspberrypi` | `dockerpi_backup` | .71 | Backup Pi (Unbound, Pi-hole failover) |
| `control_plane` | `node01` | .62 | K3s master |
| `nodes` | `node02–04` | .63–.65 | K3s workers |
| `storage` | `node03` | .64 | Longhorn storage |
| `pikvms` | `pikvm` | .59 | KVM management (user: root, python3.13) |

All Pi hosts use SSH key auth (`~/.ssh/<hostname>`) and `python3.11`.

## Architecture

### External roles (requirements.yml → roles/)

- `raspberry-pi` — Pi OS setup
- `docker` — Docker installation and container management (separate repo: `ansible-role-docker`)
- `nfs` — NFS setup
- `wol` — Wake-on-LAN

### Kubernetes manifests pattern

Each K8s service under `raspberry-pi-playbooks/cluster/kubernetes/<service>/` has two files:
- `<service>-template.yml` — raw manifest with Jinja2 variable placeholders (e.g., `{{ nhl_odds_postgres_password }}`)
- `<service>.yml` — rendered output (committed, applied by playbook)

Secrets and cluster variables come from `~/source/ansible-files/vars/cluster_vars.yml` (external, not in repo).

Services with Kubernetes manifests: `traefik`, `longhorn`, `prometheus`, `nhl-odds`, `minecraft`, `codespace`, `dashboard`, `esphome`, `helm`, `nfs`, `pi-hole`, `portainer`.

Traefik runs as a DaemonSet and handles TLS for `.kubecluster` local domains using `IngressRoute` CRDs (`traefik.io/v1alpha1`).

### Docker machine (dockerpi)

Managed via `raspberry-pi-playbooks/docker-machine/docker-setup.yml`, which calls the `docker` role. Container definitions live in `ansible-role-docker/tasks/containers/`.
