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

Cluster mode is the `valueFiles` entry in
[clusters/prod/infra/postgres-cluster.yaml](../../clusters/prod/infra/postgres-cluster.yaml):

1. Point it at `values-cluster-recovery.yaml`, merge, wait for all 3 instances ready.
2. Point it back at `values-cluster.yaml` for standalone with backups enabled.

`values-cluster-hibernate.yaml` scales the cluster down without deleting it.

## Notes

- Never delete WALs from the source archive — that breaks recovery.
- `prune: false` on the Application: removals need a deliberate `kubectl delete`.
