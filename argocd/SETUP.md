## Overview

GitOps control plane at `argocd.maxhq.io`. Every workload is an `Application` reconciled from
this repo; CI only commits versions and holds no kubeconfig. Adding anything is a new file in
`infra/` (upstream charts, values at `<component>/values.yaml`) or `apps/` (charts from
`ghcr.io/maxmorhardt/charts`, last published from the retired `charts` repo; source now lives in
`maxhq/charts`; image tag pinned by CI). The `root.yaml` app-of-apps picks
it up within ~3 min. Any non-`Application` yaml under `argocd/` **will** be applied to the cluster.

## Bootstrap

```bash
cd argocd && ./bootstrap.sh
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
| kubeseal --format yaml --cert sealed-secrets/pub-cert.pem > secrets/argocd/argocd-oidc.yaml
```

## Notes

- **Deploy**: cut a release. **Roll back**: revert the commit. **Pause**: drop `syncPolicy.automated`.
- `prune: false` on `postgres-cluster`, `storage`, `gateway` — pruning them is destructive.
