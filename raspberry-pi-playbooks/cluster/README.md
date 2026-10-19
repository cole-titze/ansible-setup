# Kubernetes Cluster

K3s cluster running on Raspberry Pis (node01-04).

## Running

```bash
# Full cluster setup
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml

# Single service (available tags: helm, longhorn, traefik, codespace, magic-mirror, folding-at-home, prometheus, minecraft)
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/raspberry-pi-cluster.yml -t <tag>

# Reset all workloads
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/reset-kubernetes.yml

# Uninstall K3s entirely
ansible-playbook -i inventories/inventory.ini raspberry-pi-playbooks/cluster/kubernetes/uninstall-kubernetes.yml
```

## Port Mapping

- Traefik: hostPorts 80/443 on every node (no NodePorts)
- Longhorn / Traefik dashboards: longhorn.kubecluster, traefik.kubecluster (basic auth)
- Codespace: 8090 -> code.kubecluster
- Magic Mirror: 8082 -> mirror.kubecluster
- Grafana: grafana.kubecluster
- Prometheus: prometheus.kubecluster
