# Dex

OIDC identity provider at `https://login.maxhq.io` (prod) and `https://login.dev.maxhq.io` (dev), federating **Google**, **Microsoft**, and **GitHub** sign-in for every maxhq app.

One Helm release in the `dex` namespace: the upstream chart (`dex/dex` from https://charts.dexidp.io), config in [values.yaml](values.yaml) with dev's hostnames in [values-dev.yaml](values-dev.yaml). The chart's built-in `httpRoute` attaches the login host to the `maxhq` Gateway.

## One-time setup

1. **Postgres**: nothing to do. The `dex` role and database are declared in
   [values-cluster.yaml](../postgres/values-cluster.yaml); the password is `cnpg-database/postgres-dex-user`.
2. **Google OAuth client**: one Web client for both clusters, with redirect URIs
   `https://login.maxhq.io/callback` and `https://login.dev.maxhq.io/callback`.
3. **Microsoft Entra app**: one multitenant + personal-accounts app for both clusters, with the same two
   redirect URIs (platform Web). Its client secret expires after at most 24 months.
4. **GitHub OAuth app**: one per cluster (GitHub allows a single callback URL each).
5. **Secret**: `dex/dex-env` per cluster ([secret.example.yaml](secret.example.yaml) lists the keys), set with
   `scripts/secrets.sh` (see [sealed-secrets](../sealed-secrets/README.md)).
6. Deploy: merge to `main`; Argo CD syncs `clusters/<cluster>/infra/dex.yaml` and the sealed `dex-env`.

## Adding a new app

1. Add a `staticClients` entry: SPAs get `public: true` + exact redirect URIs; server-side apps get `secretEnv: <APP>_CLIENT_SECRET` plus a new key in `dex-env` (`scripts/secrets.sh set <cluster> dex/dex-env <APP>_CLIENT_SECRET=`). Add the dev
   redirect URIs to `values-dev.yaml` too. `http://localhost:3000` belongs in dev only: local frontends sign in against dev's Dex, never prod's.
2. Merge; Argo CD restarts dex with the new config. The app's OIDC config: issuer `https://login.maxhq.io` (or `login.dev.maxhq.io`), its client id, scopes `openid profile email offline_access`.
