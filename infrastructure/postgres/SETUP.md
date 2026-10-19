## Overview

CloudNativePG in two Applications: the operator in `cnpg-system` and the cluster in
`cnpg-database`. Backs Dex, Grafana, and the app databases, with WAL archiving to S3.

## Secrets

Three secrets in `cnpg-database`, sealed into `clusters/<cluster>/secrets/cnpg-database/` — see
[sealed-secrets/SETUP.md](../sealed-secrets/SETUP.md). Argo applies them; nothing here is
`kubectl apply`'d by hand.

| secret | keys |
| --- | --- |
| `postgres-superuser` | `username` (`postgres`), `password` |
| `postgres-admin-user` | `username`, `password` — the database owner |
| `aws-s3-credentials` | `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` — backups |

## Recovery

Cluster modes are overlays added after `values-cluster.yaml` in the `valueFiles` of
[clusters/prod/infra/postgres-cluster.yaml](../../clusters/prod/infra/postgres-cluster.yaml):

1. Delete the `postgres-cluster` Cluster (recovery only runs when a cluster is created), add
   `values-cluster-recovery.yaml`, merge, and wait for every instance to be ready.
2. Remove the overlay so the cluster runs standalone with backups enabled again.

`values-cluster-hibernate.yaml` shuts the cluster down and keeps its volumes.

## Notes

- Never delete WALs from the source archive — that breaks recovery.
- `prune: false` on the Application: removals need a deliberate `kubectl delete`.
