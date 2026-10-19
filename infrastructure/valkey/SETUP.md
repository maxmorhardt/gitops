## Overview

Valkey for the squares services, from the [CloudPirates chart](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/valkey):
three pods on separate nodes, Sentinel failover, and an HAProxy sidecar in each pod that always
forwards to the current primary. Append-only persistence on 2Gi `local-path-retain` volumes.

It holds the event streams (`squares:events:*`, written through each service's Postgres outbox) and
short-lived state (caches, `Idempotency-Key` records, token revocations). Every key is prefixed
`squares:` and has a TTL, so `volatile-ttl` evicts caches long before streams. The services start
and keep serving without Valkey; only live updates stop.

## Access

- Clients: `valkey-master.valkey.svc:6379` (the proxy; writes always reach the primary)
- Sentinel: `valkey-sentinel.valkey.svc:26379`, master name `valkey`
- Metrics: `valkey-metrics.valkey.svc:9121`

## Users

Passwords live in the sealed `valkey-users` Secret ([secret.example.yaml](secret.example.yaml)):

- `default` - full access, used by replication, Sentinel, and the exporter
- `squares` - `squares:*` keys only, no `@dangerous` commands. Defined in [values.yaml](values.yaml)
  by the SHA-256 of its password; each `squares-<service>-env` holds
  `REDIS_URL=redis://squares:<password>@valkey-master.valkey.svc:6379/0`

To rotate: reseal `valkey-users`, update the hash (`printf %s "$PW" | sha256sum`) and each
`REDIS_URL`, then restart the StatefulSet and the squares services.

## Operations

```bash
PASS=$(kubectl -n valkey get secret valkey-users -o jsonpath='{.data.default}' | base64 -d)
kubectl -n valkey exec -it valkey-0 -c valkey -- valkey-cli --user default --pass "$PASS" INFO replication
```

Contests' position in each stream is in `contests.stream_offsets` (`last_id` is `<unix ms>-<seq>`).

## Losing data

A failover can drop the last writes before replication caught up, and losing every volume drops
everything. Caches refill, revocations return on the next accounts restart, and viewers get a fresh
snapshot. Unread games and users events need a replay from the outbox, which keeps published rows
for 24 hours:

```sql
UPDATE games.outbox SET published_at = NULL
 WHERE published_at >= to_timestamp(<contests-games ms> / 1000.0) - interval '1 minute';
UPDATE accounts.outbox SET published_at = NULL
 WHERE published_at >= to_timestamp(<contests-users ms> / 1000.0) - interval '1 minute';
```

The relays append them again in order; re-applying an event contests already saw is harmless.
