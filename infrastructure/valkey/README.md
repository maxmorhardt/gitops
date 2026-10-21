# Valkey

Valkey for the squares services, from the [CloudPirates chart](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/valkey):
three pods on separate nodes, Sentinel failover, and an HAProxy sidecar in each pod that always forwards to the current primary. Append-only persistence on `local-path-retain` volumes.

## Access

- Clients: `valkey-master.valkey.svc:6379` (the proxy; writes always reach the primary)
- Sentinel: `valkey-sentinel.valkey.svc:26379`, master name `valkey`
- Metrics: `valkey-metrics.valkey.svc:9121`
