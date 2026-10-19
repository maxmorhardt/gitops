# Secrets per cluster

Every value here is sealed with the cluster's own key into `clusters/<cluster>/secrets/<namespace>/<name>.yaml`
(see [sealed-secrets/SETUP.md](../sealed-secrets/SETUP.md)). Fetch the cert once Argo CD has synced sealed-secrets:

```bash
kubeseal --context <cluster> --controller-name sealed-secrets --controller-namespace sealed-secrets \
  --fetch-cert > clusters/<cluster>/pub-cert.pem
```

Seal a generic secret:

```bash
kubectl create secret generic <name> -n <namespace> --dry-run=client -o yaml \
  --from-literal=<KEY>=<value> ... \
  | kubeseal --format yaml --cert clusters/<cluster>/pub-cert.pem \
  > clusters/<cluster>/secrets/<namespace>/<name>.yaml
```

Generate passwords and tokens with `openssl rand -hex 24`. Prod and dev use **different** values for
everything except the origin certificate and the OAuth app credentials noted below.

## Both clusters

| namespace / name | type | keys | value |
| --- | --- | --- | --- |
| `cnpg-database/postgres-superuser` | `kubernetes.io/basic-auth` | `username`, `password` | `postgres`, generated |
| `cnpg-database/postgres-admin-user` | `kubernetes.io/basic-auth` | `username`, `password` | `maxmorhardt`, generated (owns the `maxhq` database) |
| `cnpg-database/postgres-dex-user` | `kubernetes.io/basic-auth` | `username`, `password` | `dex`, same password as `DEX_POSTGRES_PASSWORD` |
| `dex/dex-env` | generic | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `DEX_POSTGRES_PASSWORD`, `ARGOCD_CLIENT_SECRET`, `AGES_CLIENT_SECRET` | Google client can be shared (both callbacks registered); GitHub needs one OAuth app per cluster (`https://login.maxhq.io/callback`, `https://login.dev.maxhq.io/callback`) |
| `argocd/argocd-oidc` | generic | `clientSecret` | same as `ARGOCD_CLIENT_SECRET` |
| `valkey/valkey-users` | generic | `default`, `squares` | generated; `squares` must hash to the `user squares on #<sha256>` line in `valkey/values.yaml` (`printf %s <password> \| sha256sum`) — update that line if you generate a new one |
| `kube-system/kured-discord` | generic | `url` | Discord webhook in Shoutrrr form: `discord://<token>@<id>` |
| `squares/squares-contests-env` | generic | see below | |
| `squares/squares-games-env` | generic | see below | |
| `squares/squares-accounts-env` | generic | see below | |
| `squares/squares-realtime-env` | generic | `ALLOWED_ORIGINS`, `INTERNAL_API_TOKEN`, `REDIS_URL` | |

## Prod only

| namespace / name | type | keys | value |
| --- | --- | --- | --- |
| `envoy-gateway-system/maxhq.io-tls` | `kubernetes.io/tls` | `tls.crt`, `tls.key` | Cloudflare origin certificate for `maxhq.io` + `*.maxhq.io`: `kubectl create secret tls maxhq.io-tls -n envoy-gateway-system --cert=origin.pem --key=origin-priv.pem` |
| `cnpg-database/aws-s3-credentials` | generic | `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` | an access key for IAM user `srv-s3` (policy `maxhq-backups-access-policy`) |

## Dev only

| namespace / name | type | keys | value |
| --- | --- | --- | --- |
| `cert-manager/cloudflare-api-token` | generic | `api-token` | Cloudflare token with Zone → DNS: Edit on `maxhq.io`, for DNS-01 |
| `cert-manager/zerossl-eab` | generic | `hmac` | ZeroSSL → Developer → EAB HMAC key (its key ID goes in `cert-manager/manifests/cluster-issuer.yaml`) |

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
