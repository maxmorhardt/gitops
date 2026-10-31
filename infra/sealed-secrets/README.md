# Sealed Secrets

Encrypts secrets so they can live in git. A `SealedSecret` is encrypted with a public cert; only
the in-cluster controller holds the private key and unseals it into a real `Secret`. Sealed
manifests live in [clusters/<cluster>/secrets/](../../clusters/) and are applied by their own Application
(`sync-wave: -1`, so the CRD exists before anything creates a `SealedSecret`).

## Use

Every secret is sealed with its cluster's own key into `clusters/<cluster>/secrets/<namespace>/<name>.yaml`.
[scripts/secrets.sh](../../scripts/secrets.sh) reads and writes them; it needs `kubectl`, `kubeseal`, `jq`,
and `yq`:

```bash
scripts/secrets.sh get prod squares/squares-games-env              # every KEY=value
scripts/secrets.sh get prod squares/squares-games-env DB_PASSWORD  # one value
scripts/secrets.sh set prod squares/squares-games-env DB_MAX_OPEN_CONNS=10 DB_PASSWORD=
scripts/secrets.sh new prod squares/new-thing API_TOKEN= --type Opaque --label app=x
```

`KEY=` with nothing after it prompts for the value without echoing it, so it never lands in shell history;
`KEY=@path` reads it from a file (certificates, keys). Commit the changed files under
`clusters/<cluster>/secrets/` and Argo CD applies them. Generate passwords with `openssl rand -hex 24`.

For bigger edits, `scripts/secrets.sh unseal prod --namespace squares` (or `--all`, or `--secret <ns>/<name>`)
writes plain YAML to the gitignored `.secrets/prod/`; edit it, `scripts/secrets.sh seal prod` with the same
flag, then `scripts/secrets.sh clean`. Seal only what you changed: sealing re-encrypts, so every sealed file
shows a diff.

Decryption uses `scripts/keys/<cluster>.yaml` when present, and the live cluster otherwise. Each cluster's
public cert is committed at `clusters/<cluster>/pub-cert.pem`; the script fetches it if missing.

Key renewal is off (`keyrenewperiod: '0'`), so each cluster keeps the one key it was created with.

## Back up the sealing key

Lose a cluster's private key and **every sealed manifest for it becomes undecryptable**; the only way
back is reissuing each value. `scripts/secrets.sh backup-key <cluster>` saves it to
`scripts/keys/<cluster>.yaml`, which is gitignored; the script also uses it to decrypt without the
cluster. Keep a second copy off this machine (a password manager
attachment works).

## Rebuild a cluster with its key

Restore the key **before** Argo CD installs the controller, so the controller adopts it instead of
generating a new one and every committed SealedSecret keeps working:

```bash
bootstrap/namespaces.sh
kubectl --context <cluster> apply -f scripts/keys/<cluster>.yaml
```

To give a cluster a new key instead: unseal everything first while the old key still works
(`scripts/secrets.sh unseal <cluster> --all`), let the controller generate the new key, delete
`clusters/<cluster>/pub-cert.pem`, run `scripts/secrets.sh backup-key <cluster>`, then
`scripts/secrets.sh seal <cluster> --all`.
