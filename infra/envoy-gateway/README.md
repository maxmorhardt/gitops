# Envoy Gateway

Gateway API implementation fronting all HTTP traffic for `maxhq.io` (prod) and `dev.maxhq.io` (dev).

Two pieces:

1. **envoy-gateway** (this directory): the upstream controller chart, plus the Gateway API CRDs. Synced from `clusters/<cluster>/infra/envoy-gateway.yaml`.
2. **gateway**: chart from maxhq (published to `ghcr.io/maxmorhardt/charts`) with the actual Gateway resources: the `maxhq` GatewayClass + Gateway (listeners for `<domain>` and `*.<domain>` on 443, http→https redirect on 80), the `EnvoyProxy` config (2 proxy replicas), prod's cloudflared, a `ClientTrafficPolicy` resolving the real client IP from `X-Forwarded-For`, and that strips client-supplied identity headers (`X-Auth-*`, `X-Internal-Token`) before any route sees them. Synced from `clusters/<cluster>/apps/gateway.yaml`, which sets the cluster's domain and TLS secret.

Apps attach by creating an `HTTPRoute` in their own namespace with `parentRefs` pointing at `maxhq` / `envoy-gateway-system`. The Gateway allows routes from all namespaces.

## Prerequisites

The wildcard TLS secret must exist in `envoy-gateway-system`: in prod the sealed Cloudflare origin
certificate `maxhq.io-tls`, in dev `dev.maxhq.io-tls` issued by [cert-manager](../cert-manager/README.md).

Prod also runs cloudflared (`tunnel.enabled`), which needs the sealed `cloudflared-token` in
`envoy-gateway-system`: the token from `terraform output -raw prod_tunnel_token` in maxhq's
`infra/terraform/cloudflare`.

```bash
scripts/secrets.sh new prod envoy-gateway-system/cloudflared-token token=<token>
```

The tunnel's ingress rules and the DNS cutover are in maxhq's `infra/terraform/README.md`.

## Notes

- Client IP: the `ClientTrafficPolicy` walks `X-Forwarded-For` right-to-left and takes the first address outside the pod network (`trustedCIDRs`). In prod the proxy's only client is cloudflared, so that is the visitor's address as Cloudflare saw it. Prod's proxy Service is `ClusterIP`, so nothing listens on the nodes' public IPs.
- Rate limits: per-route `BackendTrafficPolicy` (Local type) in each app chart, counted per proxy replica.
- Request body size caps moved into the apps themselves (`request_size` middleware); the gateway does not enforce one.
- Authentication: the squares API validates OIDC tokens at the gateway. Its chart's `SecurityPolicy` checks the bearer JWT against Dex (`https://login.maxhq.io/keys`, audiences `squares` and `squares-mobile`) and copies the claims into `X-Auth-Email`, `X-Auth-Name`, `X-Auth-Email-Verified`, `X-Auth-Iat` and `X-Auth-Exp`. The JWT is optional so public routes still work; the services reject protected routes without `X-Auth-Email`. The header stripping above is what makes those headers trustworthy, so it must ship before or with any chart that relies on them.
- Server-sent events: the squares realtime route (`/squares/events/...`) sets `timeouts.request: 0s` so long-lived streams are not cut off; the service sends a heartbeat every 25s to keep idle connections open through Cloudflare.
