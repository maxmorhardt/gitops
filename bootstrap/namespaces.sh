#!/usr/bin/env bash
set -euo pipefail

namespaces=(
  ages
  argocd
  cert-manager
  cnpg-database
  dex
  envoy-gateway-system
  kube-system
  maxhq
  olympics
  squares
  valkey
)

for namespace in "${namespaces[@]}"; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done
