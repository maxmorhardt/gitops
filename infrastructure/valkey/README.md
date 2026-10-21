# Valkey

Valkey for the squares services, from the [CloudPirates chart](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/valkey):
three pods on separate nodes, Sentinel failover, and an HAProxy sidecar in each pod that always forwards to the current primary. Append-only persistence on `local-path-retain` volumes.

## Access

- Clients: `valkey-master.valkey.svc:6379` (the proxy; writes always reach the primary)
- Sentinel: `valkey-sentinel.valkey.svc:26379`, master name `valkey`
- Metrics: `valkey-metrics.valkey.svc:9121`

## Users

Two users, both from SealedSecrets in `clusters/<cluster>/secrets/valkey/`:

- `default`: its password is the `default` key of `valkey-users`. Replication and Sentinel use it.
- `squares`: limited to `squares:*` keys, with no dangerous commands. Its ACL line is `users.conf` in `valkey-acl`, which `values.yaml` loads with `include /etc/valkey-acl/users.conf`. The squares services log in with the `squares` key of `valkey-users`.

The chart can't mount extra volumes, so Argo CD renders it through [`kustomization.yaml`](kustomization.yaml), which patches the `valkey-acl` mount into the StatefulSet. The chart version lives there too.

