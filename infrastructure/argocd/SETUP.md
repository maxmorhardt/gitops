## Overview

GitOps control plane per cluster, at `argocd.maxhq.io` (prod) and `argocd.dev.maxhq.io` (dev).
Every workload is an `Application` reconciled from this repo; CI only commits versions and holds
no kubeconfig. Adding anything is a new file in `clusters/<cluster>/infra/` (upstream charts,
values at `infrastructure/<component>/values.yaml`) or `clusters/<cluster>/apps/` (charts from
`maxhq/charts`, image tag pinned by CI). The cluster's `root.yaml` app-of-apps picks it up within
~3 min. Any non-`Application` yaml under `clusters/<cluster>/` **will** be applied to the cluster.

## Bootstrap

```bash
bootstrap/argocd.sh <cluster>
```

It **adopts** already-running resources

## SSO

Federates to the cluster's [Dex](../dex/SETUP.md) on the verified email claim (`rbac.scopes: [email]`).
Admins are listed per-email in `policy.csv` - no role for default users. The oidc secret must exist
in both Dex's `dex-env` and sealed here, and needs the `part-of` label or Argo can't resolve it:

```bash
kubectl create secret generic argocd-oidc --namespace argocd \
  --from-literal=clientSecret="$(openssl rand -hex 32)" --dry-run=client -o yaml \
| kubectl label --local -f - app.kubernetes.io/part-of=argocd -o yaml \
| kubeseal --format yaml --cert clusters/<cluster>/pub-cert.pem > clusters/<cluster>/secrets/argocd/argocd-oidc.yaml
```

## Notes

- **Deploy**: cut a release. **Roll back**: revert the commit. **Pause**: drop `syncPolicy.automated`.
- `prune: false` on `postgres-cluster`, `storage`, `gateway` — pruning them is destructive.
