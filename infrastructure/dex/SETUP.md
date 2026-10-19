## Overview

OIDC identity provider at `https://login.maxhq.io`, federating **Google** and **GitHub** sign-in for all maxhq apps. Replaces Authentik.

One Helm release in the `dex` namespace: the upstream chart (`dex/dex` from https://charts.dexidp.io), config in [values.yaml](values.yaml). The chart's built-in `httpRoute` attaches `login.maxhq.io` to the `maxhq` Gateway.

## One-time setup

1. **Postgres**: create the `dex` database and user on the CNPG cluster:
   ```sql
   CREATE USER dex WITH PASSWORD '...';
   CREATE DATABASE dex OWNER dex;
   ```
2. **Google OAuth client**: Google Cloud Console → APIs & Services → Credentials → Create OAuth client ID (Web application). Authorized redirect URI: `https://login.maxhq.io/callback`. Configure the consent screen (external, publish).
3. **GitHub OAuth app**: Settings → Developer settings → OAuth Apps → New. Authorization callback URL: `https://login.maxhq.io/callback`.
4. Create the secret: `cp secret.example.yaml secret.yaml`, fill it in, then seal it and
   delete the plaintext (see [sealed-secrets/SETUP.md](../sealed-secrets/SETUP.md))
5. Deploy: merge to `main` - Argo CD syncs the [dex Application](../../clusters/prod/infra/dex.yaml)
   and the sealed `dex-env` secret.

## Adding a new app

1. Add a `staticClients` entry: SPAs get `public: true` + exact redirect URIs; server-side apps get `secretEnv: <APP>_CLIENT_SECRET` plus a new key in `dex-env` (`openssl rand -hex 32`).
2. Redeploy dex. The app's OIDC config: issuer `https://login.maxhq.io`, its client id, scopes `openid profile email offline_access`.
