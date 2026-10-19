## Overview

Encrypts secrets so they can live in git. A `SealedSecret` is encrypted with a public cert; only
the in-cluster controller holds the private key and unseals it into a real `Secret`. Sealed
manifests live in [clusters/<cluster>/secrets/](../../clusters/) and are applied by their own Application
(`sync-wave: -1`, so the CRD exists before anything creates a `SealedSecret`).

## Use

[scripts/secrets.sh](../../scripts/secrets.sh) unseals, edits, and seals; see
[clusters/SECRETS.md](../../clusters/SECRETS.md). It needs `kubectl`, `kubeseal`, `jq`, and `yq`. Each
cluster's public cert is committed at `clusters/<cluster>/pub-cert.pem`; the script fetches it if missing.

Key renewal is off (`keyrenewperiod: '0'`), so each cluster keeps the one key it was created with.

## Back up the sealing key

Lose a cluster's private key and **every sealed manifest for it becomes undecryptable**; the only way
back is reissuing each value. Keep one backup per cluster outside the repo (a password manager
attachment works):

```bash
kubectl --context <cluster> get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > <cluster>-sealed-secrets-key.yaml
```

## Rebuild a cluster with its key

Restore the key **before** Argo CD installs the controller, so the controller adopts it instead of
generating a new one and every committed SealedSecret keeps working:

```bash
bootstrap/namespaces.sh
kubectl --context <cluster> apply -f <cluster>-sealed-secrets-key.yaml
```

Without the backup, let the controller make a new key, then re-seal everything from the old values:
`scripts/secrets.sh unseal <cluster> --all --key <old key>` (or unseal the other cluster and adjust),
delete `clusters/<cluster>/pub-cert.pem`, and run `scripts/secrets.sh seal <cluster> --all`.
