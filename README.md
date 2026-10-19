# gitops

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Tailscale](https://img.shields.io/badge/tailscale-242424?style=for-the-badge&logo=tailscale&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=for-the-badge&logo=Cloudflare&logoColor=white)
![Envoy Gateway](https://img.shields.io/badge/Envoy%20Gateway-AC6199?style=for-the-badge&logo=envoyproxy&logoColor=white)
![Dex](https://img.shields.io/badge/Dex-3778E1?style=for-the-badge&logo=openid&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![Valkey](https://img.shields.io/badge/valkey-6983FF?style=for-the-badge)
![kured](https://img.shields.io/badge/kured-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)

Desired state for the `dev` and `prod` k3s clusters. Argo CD on each cluster reconciles its own
directory under [clusters/](clusters/); nothing reaches a cluster except through a commit here.

| | dev | prod |
| --- | --- | --- |
| Nodes | Raspberry Pis at home | Contabo VPSes |
| Hostnames | `dev.maxhq.io`, `<app>.dev.maxhq.io` (tailnet only) | `maxhq.io`, `<app>.maxhq.io` |
| Deploys | every merge to an app's `main`: CI sets `sha-<commit>` images and `0.0.0-sha-<commit>` charts | every release, after approval: the promoted image or the released chart version |

## How it fits together

- **Ingress**: the `maxhq` Envoy Gateway on 443 of every node → apps by `HTTPRoute`. Prod's hostnames are
  Cloudflare-proxied A records to the prod nodes (origin certificate); dev's resolve to dev's Tailscale IPs,
  so dev exists only on the tailnet (certificate from Let's Encrypt via cert-manager). Node-to-node traffic runs
  over Tailscale.
- **Auth**: Dex federates Google and GitHub sign-in; the gateway validates tokens for the APIs.
- **Data**: CloudNativePG for PostgreSQL (prod backs up to S3), Valkey with Sentinel for caches and
  event streams.
- **Secrets**: SealedSecrets, sealed per cluster and edited with `scripts/secrets.sh`; the list is [clusters/SECRETS.md](clusters/SECRETS.md).
- **Upgrades**: kured reboots nodes one at a time; system-upgrade-controller tracks k3s stable.

Outside the clusters, the [maxhq](https://github.com/maxmorhardt/maxhq) monorepo holds the app
charts, the k3s bootstrap, and Terraform for DNS, backups, and GitHub settings.

## Bring up a cluster

```bash
# 1. nodes: maxhq/infra/k3s/bootstrap
python main.py up <cluster>

# 2. namespaces, then the cluster's sealing key backup (infrastructure/sealed-secrets/SETUP.md)
kubectl config use-context <cluster>
bootstrap/namespaces.sh
kubectl apply -f scripts/keys/<cluster>.yaml

# 3. Argo CD with the cluster's root app; it syncs everything else, committed secrets included
bootstrap/argocd.sh <cluster>
```

## Layout

| path | |
| --- | --- |
| `clusters/<cluster>/root.yaml` | app-of-apps for the cluster |
| `clusters/<cluster>/infra/` | one Application per infrastructure component |
| `clusters/<cluster>/apps/` | one Application per app, charts from `ghcr.io/maxmorhardt/charts` (public from maxhq, private from maxhq-private) at a pinned version |
| `clusters/<cluster>/secrets/` | that cluster's SealedSecrets |
| `infrastructure/<component>/` | `values.yaml` (prod), `values-dev.yaml` (dev's differences), manifests, `SETUP.md` runbook |
| `bootstrap/` | bringing up a bare cluster: namespaces, then Argo CD |
| `scripts/` | day-to-day tools: `secrets.sh` (get, set, new, unseal, seal, backup-key), Postgres port-forward, dump, and restore |

CI renders every chart and validates every manifest on pull requests; it never touches a cluster.
