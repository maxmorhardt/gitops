# Secrets per cluster

Every secret is sealed with its cluster's own key into `clusters/<cluster>/secrets/<namespace>/<name>.yaml`;
only that cluster's sealed-secrets controller can decrypt it. Work on them in plain text with
[scripts/secrets.sh](../scripts/secrets.sh), which keeps the plain copies in the gitignored `.secrets/`:

```bash
# read: plain Secret YAML (values decoded) from the live cluster
scripts/secrets.sh unseal prod --namespace squares        # or --all, or --secret squares/squares-games-env

# change: edit .secrets/prod/squares/squares-games-env.yaml, then encrypt it back and commit
scripts/secrets.sh seal prod --secret squares/squares-games-env

# add: start a new one, fill in stringData, seal it
scripts/secrets.sh new prod --secret squares/new-thing

# done: drop the plain copies
scripts/secrets.sh clean
```

Seal only what you changed: sealing re-encrypts, so every sealed file touched shows a diff. With the cluster
down, `unseal ... --key <sealing-key backup>` decrypts offline (see
[sealed-secrets/SETUP.md](../infrastructure/sealed-secrets/SETUP.md)).

Generate passwords and tokens with `openssl rand -hex 24`.

## Both clusters

| namespace / name | type | keys | value |
| --- | --- | --- | --- |
| `cnpg-database/postgres-superuser` | `kubernetes.io/basic-auth` | `username`, `password` | `postgres`, generated |
| `cnpg-database/postgres-admin-user` | `kubernetes.io/basic-auth` | `username`, `password` | `maxmorhardt`, generated (owns the `maxhq` database) |
| `cnpg-database/postgres-dex-user` | `kubernetes.io/basic-auth` | `username`, `password` | `dex`, same password as `DEX_POSTGRES_PASSWORD` |
| `cnpg-database/postgres-olympics-user` | `kubernetes.io/basic-auth` | `username`, `password` | `olympics`, generated (owns the `olympics` database) |
| `dex/dex-env` | generic | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `DEX_POSTGRES_PASSWORD`, `ARGOCD_CLIENT_SECRET`, `AGES_CLIENT_SECRET` | Google client can be shared (both callbacks registered); GitHub needs one OAuth app per cluster (`https://login.maxhq.io/callback`, `https://login.dev.maxhq.io/callback`) |
| `argocd/argocd-oidc` | generic | `clientSecret` | same as `ARGOCD_CLIENT_SECRET` |
| `argocd/repo-maxhq-private` | generic, label `argocd.argoproj.io/secret-type=repository` | `type`, `url`, `sshPrivateKey` | read-only deploy key on `maxhq-private`, one per cluster (`argocd-dev`, `argocd-prod`) |
| `valkey/valkey-users` | generic | `default`, `squares` | generated; `squares` must hash to the `user squares on #<sha256>` line in `infrastructure/valkey/values.yaml` (`printf %s <password> \| sha256sum`) — update that line if you generate a new one |
| `kube-system/kured-discord` | generic | `url` | Discord webhook in Shoutrrr form: `discord://<token>@<id>` |
| `squares/squares-contests-env` | generic | see below | |
| `squares/squares-games-env` | generic | see below | |
| `squares/squares-accounts-env` | generic | see below | |
| `squares/squares-realtime-env` | generic | `ALLOWED_ORIGINS`, `INTERNAL_API_TOKEN`, `REDIS_URL` | |
| `olympics/olympics-api-env` | generic | `DB_*` (`olympics` database and user), `OIDC_CLIENT_ID`, `OIDC_ISSUER`, `ALLOWED_ORIGINS`, `ADMIN_EMAILS` | |
| `ages/docker-secret` | `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` | Docker Hub read token for the private `maxmorhardt/ages` image |
| `ages/ages-oidc-client` | generic | `client-secret` | same as `AGES_CLIENT_SECRET` |
| `ages/ages-email-env` | generic | `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `FROM_EMAIL`, `TO_EMAILS` | Zoho, as for squares accounts |

## Prod only

| namespace / name | type | keys | value |
| --- | --- | --- | --- |
| `envoy-gateway-system/maxhq.io-tls` | `kubernetes.io/tls` | `tls.crt`, `tls.key` | Cloudflare origin certificate for `maxhq.io` + `*.maxhq.io`: `kubectl create secret tls maxhq.io-tls -n envoy-gateway-system --cert=origin.pem --key=origin-priv.pem` |
| `cnpg-database/aws-s3-credentials` | generic | `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` | an access key for IAM user `srv-s3` (policy `maxhq-backups-access-policy`) |

## Dev only

| namespace / name | type | keys | value |
| --- | --- | --- | --- |
| `cert-manager/cloudflare-api-token` | generic | `api-token` | Cloudflare token with Zone → DNS: Edit on `maxhq.io`, for DNS-01 |

Dev's TLS certificate is issued by cert-manager into `envoy-gateway-system/dev.maxhq.io-tls`; dev has no backups, so no AWS credentials.

## squares service env

| key | prod | dev |
| --- | --- | --- |
| `ALLOWED_ORIGINS` | `https://squares.maxhq.io` | `https://squares.dev.maxhq.io` |
| `DB_HOST` | `postgres-cluster-rw.cnpg-database.svc.cluster.local` | same |
| `DB_PORT` / `DB_SSL_MODE` | `5432` / `require` | same |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` | `maxhq` / `maxmorhardt` / `postgres-admin-user` password | same, with dev's password |
| `DB_READ_HOST` | `postgres-cluster-ro.cnpg-database.svc.cluster.local` | same |
| `DB_READ_*` (port, name, user, password, SSL mode) | as `DB_*` | as `DB_*` |
| `DB_MAX_OPEN_CONNS` / `DB_MAX_IDLE_CONNS` | optional, default `20` / `5` | optional, `5` / `2` keeps the Pis light |
| `REDIS_URL` | `redis://squares:<valkey squares password>@valkey-master.valkey.svc:6379/0` | same, dev's password |
| `INTERNAL_API_TOKEN` | generated, identical across the four services | same rule, dev's own value |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASSWORD` (accounts) | Zoho: `smtp.zoho.com` / `587` / `support@maxhq.io` / app password | same, or a test inbox |
| `SUPPORT_EMAIL` (accounts) | `support@maxhq.io` | same |
| `TURNSTILE_SECRET_KEY` (accounts) | the widget's secret | `1x0000000000000000000000000000000AA` (Cloudflare's always-pass test secret, matching the dev site key) |

Which service gets which keys: contests and games `ALLOWED_ORIGINS`, `DB_*`, `REDIS_URL`
(contests also `INTERNAL_API_TOKEN`); accounts all of the above plus SMTP, `SUPPORT_EMAIL`, and
`TURNSTILE_SECRET_KEY`; realtime only `ALLOWED_ORIGINS`, `INTERNAL_API_TOKEN`, `REDIS_URL`.
