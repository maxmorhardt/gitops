## Overview

Dev only. Dev is reachable only on the tailnet, so Cloudflare's proxy and origin certificate don't
apply; cert-manager gets a publicly trusted certificate for `dev.maxhq.io` and `*.dev.maxhq.io`
from Let's Encrypt instead. It proves ownership with a DNS-01 TXT record in Cloudflare, so the CA never
connects to the cluster, and renews on its own before expiry.

The gateway's dev listeners read the result from `dev.maxhq.io-tls` in `envoy-gateway-system`.

## Credentials

A Cloudflare API token with Zone → DNS: Edit on `maxhq.io`, as the
`cert-manager/cloudflare-api-token` secret (key `api-token`). Let's Encrypt needs no account;
cert-manager registers one on first use and keeps its key in `letsencrypt-account`.

