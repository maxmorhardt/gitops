## Overview

[k3s automated upgrades](https://docs.k3s.io/upgrades/automated). Control plane first via
`server-plan`, then workers one at a time via `agent-plan`.

[kustomization.yaml](kustomization.yaml) pulls the upstream CRDs and controller manifests as
remote resources alongside [plans.yaml](plans.yaml), so the repo-server needs egress to
github.com.

## Schedule

Both plans only create upgrade jobs Wednesday 02:00–04:00 America/New_York

## Verify

```bash
kubectl get plans -n system-upgrade
kubectl get jobs -n system-upgrade
kubectl get nodes -o wide
```
