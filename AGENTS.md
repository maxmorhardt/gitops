# AGENTS

## Project Context

- Project: Self-Hosted Kubernetes Stack, GitOps state (`github.com/maxmorhardt/gitops`, formerly `infra`)
- Language: YAML (Helm values, Kubernetes manifests, Argo CD Applications), plus shell for bootstrap
- Purpose: The GitOps source of truth for a self-hosted K3s cluster. Argo CD reconciles everything here into the cluster.
- Target environments: A single on-premises K3s cluster with Tailscale on nodes, high availability at the application level.
- Related repos: `maxhq` (the monorepo: apps whose releases set `image.tag`, the chart source for everything in `clusters/*/apps`, and the Terraform and k3s bootstrap for what runs outside the cluster), `workflows` (the shared validation workflows this repo's CI calls).

**Editing a file and merging to `main` is the deploy.** There is no `helm upgrade` step, no per-component `deploy.sh`, and no CI workflow anywhere that holds a kubeconfig.

## Repository Layout

- `clusters/<cluster>/` - one Argo CD instance per cluster (`dev`, `prod`), each reconciling only its own directory.
  - `root.yaml` - the app-of-apps for the cluster.
  - `infra/*.yaml` - one `Application` per infrastructure component, pointing at that component's directory here or at an upstream chart with its values from here.
  - `apps/*.yaml` - one `Application` per app: the chart from `oci://ghcr.io/maxmorhardt/charts` at a pinned `targetRevision` (public charts from maxhq, private ones from maxhq-private), `image.tag` as a Helm parameter, and dev's hostname overrides inline.
  - `secrets/<namespace>/` - that cluster's SealedSecrets, sealed with its own `pub-cert.pem`.
- `clusters/SECRETS.md` - every secret each cluster needs, its keys, and where the values come from.
- `infrastructure/<component>/` - one directory per infra component (`argocd/`, `cert-manager/` (dev only), `dex/`, `envoy-gateway/`, `kured/`, `postgres/`, `sealed-secrets/`, `storage/`, `system-upgrade-controller/`, `valkey/`): `values.yaml` is prod, `values-dev.yaml` holds dev's differences, plus a `README.md` runbook.
- `bootstrap/argocd.sh <cluster>` - installs Argo CD on a cluster and applies its root app. Run by hand.
- `bootstrap/namespaces.sh` - creates the namespaces secrets land in, before Argo CD exists.
- `.github/workflows/ci.yml` - chart and manifest validation via the shared workflows, fanning into the `Validate Complete` check the rulesets require. **Never applies to the cluster.**

## Core Principles

1. Every change is a deploy
   - Treat a merge to `main` as a production rollout.
   - Argo runs with `prune: true` and `selfHeal: true`, so deleting a resource from git deletes it from the cluster, and a manual `kubectl edit` is reverted on the next sync.
2. Git is the only source of truth
   - Nothing reaches the cluster except through a commit here. Every version running is a commit you can read, review, and revert.
3. CI never touches the cluster
   - No workflow holds a kubeconfig or cluster credentials. Argo pulls; CI does not push.
   - Argo CD itself is the one exception, bootstrapped by hand because it cannot deploy itself from nothing.
4. Secrets are encrypted, never plaintext
   - Only SealedSecrets are committed. The sealing key is restored out of band.
5. Separation of concerns with `maxhq`
   - `maxhq` holds chart source. This repo holds which version of that chart runs, and where.
6. Ownership of pinned lines
   - `image.tag` and `targetRevision` (the chart version) in `clusters/<cluster>/apps/` are written by CI: dev by every merge to an app's `main`, prod by each image or chart release after approval. Editing them by hand works but is overwritten by the next deploy.
7. Runbooks live beside config
   - Each component's `README.md` is its operational runbook and stays current with its values file.

## Agent Instructions

- Make the smallest safe change that solves the requested problem.
- Change infra behavior by editing the component's `values.yaml`, not the `Application`. Change which chart version runs by editing `targetRevision` in the `Application`.
- **Never commit a plaintext `Secret`.** Seal it first (see `infrastructure/sealed-secrets/README.md`) and put the SealedSecret in `clusters/<cluster>/secrets/<namespace>/`. Files named `*.example.yaml` are committed templates with placeholder values.
- Adding a component means creating `infrastructure/<component>/` with `values.yaml` and `README.md`, then adding `clusters/<cluster>/infra/<component>.yaml` for each cluster that runs it. Nothing runs until the `Application` exists.
- When a values change alters how a component is reached, backed up, or recovered, update its `README.md` in the same commit.
- Deleting a file is a destructive cluster operation. Confirm the resource is genuinely meant to be removed, not just moved.

## New Component Checklist

1. Create `infrastructure/<component>/` with `values.yaml` (or raw manifests).
2. Write `infrastructure/<component>/README.md` covering how it is reached, configured, backed up, and recovered.
3. Add `clusters/<cluster>/infra/<component>.yaml` with the destination namespace and sync policy.
4. Add any namespace it needs to `bootstrap/namespaces.sh`.
5. Seal and commit its secrets under `clusters/<cluster>/secrets/<namespace>/`, and list them in `clusters/SECRETS.md`.
6. Render and validate locally before pushing.

## Testing Guidance

Rendering and validating is the test. There is no test suite; a bad merge reconciles straight into the cluster.

```bash
helm template <name> <chart> -f infrastructure/<component>/values.yaml
kubeconform -strict -summary <manifest>                   # raw manifests
```

- Always render before pushing. A values key that the upstream chart does not recognize is silently ignored, so confirm the rendered output actually changed the way you expect.
- For an `Application` change, verify the chart version exists at the referenced `repoURL` first. Argo will sit in a failed sync otherwise.
- For alert or dashboard changes, validate the JSON or rule renders before committing, since Grafana and Prometheus fail quietly on malformed input.
- After merging, watch the Argo sync rather than assuming success. `prune` means a mistake can remove resources, not just fail to add them.

## Dependency Checklist

Before adding a new component or upstream chart, verify:

- Does an existing component already cover this? The stack deliberately runs one thing per concern.
- What are its CRD requirements, and what breaks if it syncs before those CRDs exist?
- What is its resource footprint? This is a small on-premises cluster, not a cloud autoscaling group.
- Does it need persistent storage, and does the `local-path-retain` StorageClass with a Retain policy suit it?
- Does it need secrets, and are those sealable?
- Is it covered by monitoring and alerting once it is running?

## Architecture

- **Clusters**: `dev` on Raspberry Pis, `prod` on Contabo VPSes; three k3s servers each on embedded etcd, all node traffic over Tailscale. Provisioned by `maxhq/infra/k3s`.
- **Ingress**: the `maxhq` Envoy Gateway listens on 443 on every node. Prod hostnames (`<app>.maxhq.io`) are Cloudflare-proxied A records to the prod nodes, with the Cloudflare origin certificate. Dev hostnames (`<app>.dev.maxhq.io`) are DNS-only records to dev's Tailscale IPs, so dev is reachable only on the tailnet, with a Let's Encrypt certificate from cert-manager. APIs share `api.maxhq.io` / `api.dev.maxhq.io` split by path prefix.
- **Auth**: Dex at `login.maxhq.io` / `login.dev.maxhq.io`, federating Google and GitHub. Email is the identity.
- **Data**: PostgreSQL via CloudNativePG (`postgres-operator` plus `postgres-cluster`; prod backs up to `s3://maxhq-backups/prod/`), Valkey with Sentinel for caches and the squares event streams.
- **Observability**: the Prometheus Operator CRDs only, so charts' ServiceMonitors and rules apply; metrics and logs are not collected in-cluster.
- **Node maintenance**: kured coordinates rolling reboots, one node at a time, running `pre-reboot.sh` first. system-upgrade-controller tracks the k3s stable channel.

## Bootstrap Order

On a bare cluster only. Everything after step 3 is reconciled automatically.

1. k3s via `maxhq/infra/k3s` (`python main.py up <cluster>`)
2. `bootstrap/namespaces.sh` against the cluster
3. `bootstrap/argocd.sh <cluster>`
4. Fetch the cluster's sealing cert, seal its secrets from `clusters/SECRETS.md`, commit them
5. Argo CD syncs the rest; apps retry until their secrets and CRDs exist

## Commit Tags

Conventional commits, enforced on PR titles by `pr-title.yml`. There is no release-please here, so the commit itself is the release.

- `feat`: New component, or new capability on an existing one.
- `fix`: Corrects broken or unsafe cluster configuration.
- `chore`: Maintenance that does not change cluster behavior, including routine version bumps.
- `ci`: Validation workflow changes.
- `docs`: a `README.md` only.

Scope is the component or app directory.

Example commit subjects:

- `feat(dex): add github connector`
- `fix(valkey): raise maxmemory to 256mb`
- `chore(argocd): bump squares targetRevision to 1.0.3`
- `docs(postgres): document the recovery values file`

## Non-Goals for Routine Changes

- Applying anything to the cluster from CI, or adding a kubeconfig to a workflow.
- Committing a plaintext Secret.
- Hand-editing `image.tag` or `targetRevision`, which CI owns.
- Adding a component directory without its Argo CD `Application`.
- Working around Argo by running `kubectl edit`, which `selfHeal` reverts anyway.
- Adding a second component that duplicates a concern the stack already covers.
- Managing cluster resources with Terraform, or out-of-cluster resources with Argo CD.
