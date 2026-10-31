# Storage

`local-path-retain` StorageClass - k3s's built-in local-path provisioner with
`reclaimPolicy: Retain` instead of the default `Delete`, so deleting a PVC leaves the data on
disk rather than wiping it. Used by anything whose data outlives its claim, notably Postgres.

Synced from `clusters/<cluster>/infra/storage.yaml` as a plain manifest
directory, not a chart.

## Notes

- `local-path` (Delete) remains the cluster default; this class is opt-in per PVC.
- `volumeBindingMode: WaitForFirstConsumer` — the volume is created on whichever node the pod
  lands on, so a PV is pinned to that node and the pod cannot reschedule elsewhere.
- Retained volumes are **not** reclaimed automatically. After deleting a PVC, the directory
  stays on the node and needs manual cleanup to free the space.
- `prune: false` on the Application: pruning a StorageClass out from under bound volumes would
  be destructive.
