#!/usr/bin/env bash
# namespaces SealedSecrets land in, created before Argo CD syncs them
set -euo pipefail

for ns in argocd cloudflared cnpg-database dex envoy-gateway-system kube-system maxhq squares valkey; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
