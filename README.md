# Self-Hosted Kubernetes Stack

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Tailscale](https://img.shields.io/badge/tailscale-242424?style=for-the-badge&logo=tailscale&logoColor=white)
![Envoy Gateway](https://img.shields.io/badge/Envoy%20Gateway-AC6199?style=for-the-badge&logo=envoyproxy&logoColor=white)
![Dex](https://img.shields.io/badge/Dex-3778E1?style=for-the-badge&logo=openid&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232671E5.svg?style=for-the-badge&logo=githubactions&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%23844FBA.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Valkey](https://img.shields.io/badge/valkey-6983FF?style=for-the-badge)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)
![Alertmanager](https://img.shields.io/badge/Alertmanager-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/grafana-%23F46800.svg?style=for-the-badge&logo=grafana&logoColor=white)
![Loki](https://img.shields.io/badge/loki-F46800?style=for-the-badge&logo=grafana&logoColor=white)
![Alloy](https://img.shields.io/badge/alloy-00D4AA?style=for-the-badge&logo=grafana&logoColor=white)
![kured](https://img.shields.io/badge/kured-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)

## Overview
A comprehensive self-hosted Kubernetes (K3s) infrastructure stack with production-ready services for container orchestration, access management, authentication, data persistence, CI/CD, monitoring, and logging. Designed for on-premises deployment with high availability.

## Features
- **Container Orchestration** with Kubernetes (K3s)
- **Persistent Storage** with local-path-retain StorageClass (Retain reclaim policy)
- **Traffic Management** via Envoy Gateway (Gateway API) — one gateway for all hostnames, APIs path-routed behind `api.maxstash.io/*`
- **Authentication** via Dex OIDC, federating Google and GitHub sign-in
- **Data Persistence** with PostgreSQL HA cluster and Valkey for caches and event streams
- **GitOps CD** with Argo CD — every workload reconciled from git, self-healing and pruning
- **Out-of-Cluster IaC** with Terraform in the `maxhq` monorepo — the S3 backup bucket, Cloudflare DNS, and GitHub rulesets as code, with remote state in S3
- **Secrets in Git** with Sealed Secrets — encrypted at rest in this repo, unsealed in-cluster by the controller
- **CI Pipeline** using GitHub Actions with shared reusable workflows
- **Monitoring & Observability** with Prometheus, Grafana dashboards, and Alertmanager (Discord + email alerts, healthchecks.io dead-man's switch)
- **Centralized Logging** via Loki and Alloy data collection
- **Automated Node Maintenance** with kured — weekly coordinated reboots with pre-reboot cleanup (apt upgrade, image prune, log rotation)
- **Automated k3s Upgrades** with Rancher's system-upgrade-controller — tracks the stable release channel, control plane first, one node at a time
- **Production Ready** with resource limits, application-level replication, and security configurations

## Architecture
The stack follows a microservices architecture where each service is independently deployable with Helm charts. All HTTP traffic enters through a single Envoy Gateway (Gateway API): UIs get a hostname each, APIs share `api.maxstash.io` split by path prefix, and Dex at `login.maxstash.io` provides OIDC with Google/GitHub sign-in. Deployment is GitOps: Argo CD reconciles the cluster from this repo, and GitHub Actions only builds, tests, and commits.

```
   ┌──────────────┐   ┌─────────┐   ┌──────────────┐
   │  Kubernetes  │◀──│ Argo CD │◀──│     git      │
   │    (K3s)     │   │ (GitOps)│   │  (this repo) │
   └──────────────┘   └─────────┘   └──────────────┘
                        │
                 ┌──────▼───────┐
                 │Envoy Gateway │
                 │(Gateway API) │
                 └──────┬───────┘
       ┌────────────────┼────────────────┐
       │                │                │
  ┌────▼─────┐    ┌─────▼──────┐    ┌───▼────┐
  │   Dex    │    │Prometheus/ │    │ Loki/  │
  │  (OIDC)  │    │ Grafana    │    │ Alloy  │
  └──────────┘    │(Monitoring)│    │(Logs)  │
                  └────────────┘    └────────┘
       ┌──────────────┼──────────────┐
       │              │              │
  ┌────▼─────┐   ┌────▼─────┐   ┌───▼────┐
  │PostgreSQL│   │  Valkey  │   │ Apps   │
  │   (DB)   │   │ (Cache,  │   │        │
  └──────────┘   │ streams) │   └────────┘
                 └──────────┘
```

## Deployment

Everything in the cluster is reconciled from git by **Argo CD** — see [argocd/SETUP.md](argocd/SETUP.md). This repo is the single source of truth for cluster desired state: infra Applications in [argocd/infra/](argocd/infra/), application Applications in [argocd/apps/](argocd/apps/), and every infra `values.yaml` where it has always been.

The one exception is Argo CD itself, which cannot deploy itself from nothing: [argocd/bootstrap.sh](argocd/bootstrap.sh) installs and repairs it, run by hand from a workstation with cluster access. Keeping that local is why no CI workflow anywhere holds a kubeconfig.

On a bare cluster the bootstrap order is:

1. **Core Infrastructure**: K3s cluster with Tailscale on nodes, bootstrapped from [maxhq/infra/k3s](https://github.com/maxmorhardt/maxhq/tree/main/infra/k3s)
2. **Namespaces**: `./namespaces.sh`
3. **Argo CD**: `cd argocd && ./bootstrap.sh` — everything below is then reconciled automatically
4. **Sealing key**: restore the Sealed Secrets private key before anything that needs a secret syncs — see [sealed-secrets/SETUP.md](sealed-secrets/SETUP.md)
5. **Storage Layer**, **Database Layer** (Postgres), **Traffic Management** (Envoy Gateway), **Kube Prometheus Stack**, **Core Services** (Valkey, Loki, Alloy), **Authentication** (Dex), **kured**, **system-upgrade-controller**

### Out-of-Cluster Resources
Argo CD reconciles everything inside the cluster. What it cannot reach, the S3 bucket CNPG archives backups to, the `maxstash.io` DNS records, and the GitHub repository rulesets, is managed with Terraform in [maxhq/infra/terraform](https://github.com/maxmorhardt/maxhq/tree/main/infra/terraform). A pull request there plans every module and merging to `main` applies it. Nothing reconciles it though, so a weekly scheduled plan is the only drift signal. See its [SETUP.md](https://github.com/maxmorhardt/maxhq/blob/main/infra/terraform/SETUP.md).

### CI/CD
CI validates charts and manifests via GitHub Actions using shared reusable workflows at `maxmorhardt/workflows`. CD is Argo CD pulling from git — CI pushes nothing to the cluster. An app's release pipeline ends by committing its new image tag into [argocd/apps/](argocd/apps/).

### Node Maintenance
kured (Kubernetes Reboot Daemon) runs as a DaemonSet on all nodes including control plane. On Tuesdays at 02:00 it checks for `/var/run/reboot-required` and coordinates rolling reboots — only one node at a time. Before each reboot, `pre-reboot.sh` runs on the host to:
- Prune unused container images
- Run `apt upgrade` and autoremove
- Vacuum systemd journal (7 day retention)
- Delete log files older than 30 days
- Clear `/tmp` and `/var/tmp`

Logs are written to `/var/log/kured` on each node. Reboot notifications are sent to Discord.

### k3s Upgrades
Rancher's system-upgrade-controller watches the k3s stable release channel and rolls out new versions during a Wednesday 02:00–04:00 ET window. Control-plane nodes upgrade first via `server-plan`; workers wait on that plan to finish, then drain and upgrade one at a time via `agent-plan`. This handles the k3s version only. kured still owns OS updates and reboots. See [system-upgrade-controller/SETUP.md](system-upgrade-controller/SETUP.md).
