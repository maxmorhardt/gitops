# PostgreSQL

CloudNativePG in two Applications: the operator in `cnpg-system` and the cluster in
`cnpg-database`. Backs Dex, olympics, and squares, each in its own database owned by its own
role; `maxhq` is the cluster's initial database. Prod archives WAL and takes daily backups to
`s3://maxhq-backups/prod/`, dev has no backups.

## Secrets

The secrets in `cnpg-database`, sealed into `clusters/<cluster>/secrets/cnpg-database/` — see
[sealed-secrets/README.md](../sealed-secrets/README.md). Argo applies them; nothing here is
`kubectl apply`'d by hand.

| secret | keys |
| --- | --- |
| `postgres-superuser` | `username` (`postgres`), `password` |
| `postgres-admin-user` | `username`, `password` — owner of the `maxhq` database |
| `postgres-dex-user`, `postgres-olympics-user`, `postgres-squares-user` | `username`, `password` — the declared `dex`, `olympics`, and `squares` roles |
| `aws-s3-credentials` | `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` — prod backups only |

## Connecting locally

Postgres has no route, NodePort, or LoadBalancer; reach it through an SSH tunnel to any node over
Tailscale. Nodes can reach ClusterIPs, and `postgres-cluster-rw` always points at the primary, so
a switchover doesn't strand the connection. In DataGrip (or any client with SSH tunnelling):

- **SSH**: host `dev-1` / `prod-1`, port 22, the cluster's SSH user and key from
  the `maxhq/infra/k3s`.
- **Database**: host is the service's ClusterIP, port 5432, database `squares`.

```bash
kubectl --context <cluster> -n cnpg-database get svc postgres-cluster-rw -o jsonpath='{.spec.clusterIP}'
```

## Recovery (prod)

Cluster modes are overlays added after `values-cluster.yaml` in the `valueFiles` of
[clusters/prod/infra/postgres-cluster.yaml](../../clusters/prod/infra/postgres-cluster.yaml):

1. Delete the `postgres-cluster` Cluster (recovery only runs when a cluster is created), add
   `values-cluster-recovery.yaml`, merge, and wait for every instance to be ready.
2. Remove the overlay so the cluster runs standalone with backups enabled again.

`values-cluster-hibernate.yaml` shuts the cluster down and keeps its volumes.
