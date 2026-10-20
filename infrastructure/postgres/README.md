# PostgreSQL

CloudNativePG in two Applications: the operator in `cnpg-system` and the cluster in
`cnpg-database`. Backs Dex, olympics, and the shared `maxhq` database; prod archives WAL and
takes daily backups to `s3://maxhq-backups/prod/`, dev has no backups.

## Secrets

The secrets in `cnpg-database`, sealed into `clusters/<cluster>/secrets/cnpg-database/` — see
[sealed-secrets/README.md](../sealed-secrets/README.md). Argo applies them; nothing here is
`kubectl apply`'d by hand.

| secret | keys |
| --- | --- |
| `postgres-superuser` | `username` (`postgres`), `password` |
| `postgres-admin-user` | `username`, `password` — owner of the `maxhq` database |
| `postgres-dex-user`, `postgres-olympics-user` | `username`, `password` — the declared `dex` and `olympics` roles |
| `aws-s3-credentials` | `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` — prod backups only |

## Recovery (prod)

Cluster modes are overlays added after `values-cluster.yaml` in the `valueFiles` of
[clusters/prod/infra/postgres-cluster.yaml](../../clusters/prod/infra/postgres-cluster.yaml):

1. Delete the `postgres-cluster` Cluster (recovery only runs when a cluster is created), add
   `values-cluster-recovery.yaml`, merge, and wait for every instance to be ready.
2. Remove the overlay so the cluster runs standalone with backups enabled again.

`values-cluster-hibernate.yaml` shuts the cluster down and keeps its volumes.

## Notes

- Never delete WALs from the source archive — that breaks recovery.
- `prune: false` on the Application: removals need a deliberate `kubectl delete`.
