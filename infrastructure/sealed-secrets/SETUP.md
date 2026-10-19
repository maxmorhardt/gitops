## Overview

Encrypts secrets so they can live in git. A `SealedSecret` is encrypted with a public cert; only
the in-cluster controller holds the private key and unseals it into a real `Secret`. Sealed
manifests live in [clusters/<cluster>/secrets/](../../clusters/) and are applied by their own Application
(`sync-wave: -1`, so the CRD exists before anything creates a `SealedSecret`).

## Setup

Install `kubeseal` (`brew install kubeseal` or the Bitnami release binary), then export the public
cert once per cluster (each has its own key) — it's public and committed on purpose:

```bash
kubeseal --context <cluster> --controller-name sealed-secrets --controller-namespace sealed-secrets \
  --fetch-cert > clusters/<cluster>/pub-cert.pem
```

## Seal a secret

```bash
kubeseal --format yaml --cert clusters/<cluster>/pub-cert.pem \
  < secret.yaml > clusters/<cluster>/secrets/<namespace>/<name>.yaml && rm secret.yaml
```

If the Secret already exists in-cluster, adopt it first so the controller manages it:
`kubectl annotate secret <name> -n <ns> sealedsecrets.bitnami.com/managed=true`.

## Back up the sealing key — do this before sealing anything

Lose the private key and **every sealed manifest becomes permanently undecryptable**; recovery
means reissuing each secret from upstream.

```bash
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.yaml
```
