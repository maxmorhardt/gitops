#!/usr/bin/env bash
# namespaces SealedSecrets land in, created before Argo CD syncs them
set -euo pipefail

namespaces=(
  argocd
  cert-manager
  cnpg-database
  dex
  envoy-gateway-system
  kube-system
  maxhq
  squares
  valkey
)

for namespace in "${namespaces[@]}"; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done
