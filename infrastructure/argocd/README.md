# Argo CD

GitOps control plane per cluster, at `argocd.maxhq.io` (prod) and `argocd.dev.maxhq.io` (dev).
Every workload is an `Application` reconciled from this repo; CI only commits versions and holds
no kubeconfig. Adding anything is a new file in `clusters/<cluster>/infra/` (upstream charts,
values at `infrastructure/<component>/values.yaml`) or `clusters/<cluster>/apps/` (charts from
`ghcr.io/maxmorhardt/charts`, chart version and image tag pinned by CI). The cluster's `root.yaml` app-of-apps picks it up within
~3 min. Any non-`Application` yaml under `clusters/<cluster>/` **will** be applied to the cluster.

## Bootstrap

```bash
bootstrap/argocd.sh <cluster>
```

It adopts resources that already exist, so re-running it is safe.

## SSO

Federates to the cluster's [Dex](../dex/README.md) on the verified email claim (`rbac.scopes: [email]`).
Admins are listed per-email in `policy.csv` - no role for default users. The client secret lives in
both Dex's `dex-env` (`ARGOCD_CLIENT_SECRET`) and `argocd/argocd-oidc`, which needs the `part-of` label or
Argo can't resolve it:

```bash
scripts/secrets.sh new <cluster> argocd/argocd-oidc --label app.kubernetes.io/part-of=argocd clientSecret=
scripts/secrets.sh set <cluster> dex/dex-env ARGOCD_CLIENT_SECRET=
```

## Notifications

Every app posts to Telegram when its health has been `Degraded` for 10 minutes and when a sync fails, prefixed with the cluster (`[dev]` or `[prod]`, from `notifications.context`). Successful deploys don't post: dev deploys on every merge, and prod releases already show in GitHub. The bot's API URL (`https://api.telegram.org/bot<token>`) lives in `argocd/argocd-notifications-secret`, and the chat ID is `notifications.context.telegramChatId`:

```bash
scripts/secrets.sh new <cluster> argocd/argocd-notifications-secret --label app.kubernetes.io/part-of=argocd telegram-url=
```

## Notes

- **Deploy**: merge to an app's `main` (dev) or cut a release (prod). **Roll back**: revert the commit here. **Pause**: drop `syncPolicy.automated`.
- `prune: false` on `postgres-cluster`, `storage`, `gateway` — pruning them is destructive.
