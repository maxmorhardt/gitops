## Overview

Gateway API implementation fronting all HTTP traffic for `maxhq.io`. Replaces ingress-nginx.

Two pieces:

1. **envoy-gateway** (this directory) — the upstream controller chart, plus the Gateway API CRDs. Synced from [clusters/prod/infra/envoy-gateway.yaml](../../clusters/prod/infra/envoy-gateway.yaml).
2. **gateway** — chart in `maxhq/charts` with the actual Gateway resources: the `maxhq` GatewayClass + Gateway (listeners for `maxhq.io` and `*.maxhq.io` on 443, http→https redirect on 80), the `EnvoyProxy` config (2 proxy replicas), and a `ClientTrafficPolicy` resolving the real client IP from `X-Forwarded-For` against the trusted Cloudflare CIDRs, and that strips client-supplied identity headers (`X-Auth-*`, `X-Internal-Token`) before any route sees them. Synced from [clusters/prod/apps/gateway.yaml](../../clusters/prod/apps/gateway.yaml).

Apps attach by creating an `HTTPRoute` in their own namespace with `parentRefs` pointing at `maxhq` / `envoy-gateway-system`. The Gateway allows routes from all namespaces.

## Prerequisites

The wildcard TLS secret must exist in `envoy-gateway-system`:

```bash
kubectl get secret maxhq.io-tls -n <existing-ns> -o yaml \
  | sed 's/namespace: .*/namespace: envoy-gateway-system/' \
  | kubectl apply -f -
```

## Notes

- Client IP: the `ClientTrafficPolicy` walks `X-Forwarded-For` right-to-left and takes the first address outside the trusted Cloudflare CIDRs - the same trust model as the old nginx `proxy-real-ip-cidr` setup. The `cloudflare-cidr` cronjob keeps the CIDR list current.
- Rate limits: per-route `BackendTrafficPolicy` (Local type) in each app chart, counted per proxy replica.
- Request body size caps moved into the apps themselves (`request_size` middleware); the gateway does not enforce one.
- Authentication: the squares API validates OIDC tokens at the gateway. Its chart's `SecurityPolicy` checks the bearer JWT against Dex (`https://login.maxhq.io/keys`, audiences `squares` and `squares-mobile`) and copies the claims into `X-Auth-Email`, `X-Auth-Name`, `X-Auth-Email-Verified`, `X-Auth-Iat` and `X-Auth-Exp`. The JWT is optional so public routes still work; the services reject protected routes without `X-Auth-Email`. The header stripping above is what makes those headers trustworthy, so it must ship before or with any chart that relies on them.
- Server-sent events: the squares realtime route (`/squares/events/...`) sets `timeouts.request: 0s` so long-lived streams are not cut off; the service sends a heartbeat every 25s to keep idle connections open through Cloudflare.
