## Overview

Handles weekly node drain → pre-reboot cleanup → reboot → uncordon automatically, one node at a time.

## How it works

1. kured watches for `/var/run/reboot-required` on each node every hour
2. On Tuesday from 02:00, kured acquires a cluster-wide lock and processes one node at a time
3. kured cordons and drains the node, then calls `/usr/local/bin/pre-reboot.sh` (deployed by bootstrap)
4. The pre-reboot script: prunes container images, runs `apt upgrade`, cleans logs/tmp/firmware backups, then reboots
5. kured uncordons the node after it comes back

Pre-reboot logs are written to `/var/log/kured/pre-reboot-<date>.log` on each node.

## Prerequisites

Bootstrap must have run on all nodes (deploys `/usr/local/bin/pre-reboot.sh`).

Create the secret in the cluster before deploying:

```bash
kubectl create secret generic kured-discord \
  --namespace kube-system \
  --from-literal=url="discord://token@id"
```

## Notes

Only enable after all nodes are bootstrapped and the cluster is healthy.
