## Overview

Two `cloudflared` replicas per cluster hold outbound connections to Cloudflare; public traffic
for the cluster's hostnames arrives over them and goes to the gateway's in-cluster Service
(`envoy-maxhq.envoy-gateway-system`). No node exposes a port.

The tunnels, their hostname routes, and the DNS records are Terraform in
`maxhq/infra/terraform/cloudflare`. This directory only runs the connector.

## Token

Each cluster's tunnel token comes from Terraform:

```bash
terraform -chdir=maxhq/infra/terraform/cloudflare output -json tunnel_tokens
```

Seal it per cluster as `cloudflared-token` (key `token`) in the `cloudflared` namespace, into
`clusters/<cluster>/secrets/cloudflared/`.

## Check

```bash
kubectl -n cloudflared logs deploy/cloudflared | grep -i "registered tunnel connection"
```

The Cloudflare dashboard (Zero Trust → Networks → Tunnels) shows each tunnel as healthy with
two connectors.
