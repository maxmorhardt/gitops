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
  monitoring
  olympics
  sealed-secrets
  squares
  valkey
)

# app workloads must pass the baseline pod security standard and warn on anything short of restricted;
# infra namespaces (node-exporter, envoy, operators) need host access, so they are left unlabelled
restricted_apps=(ages maxhq olympics squares)

for namespace in "${namespaces[@]}"; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done

for namespace in "${restricted_apps[@]}"; do
  kubectl label namespace "$namespace" --overwrite \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/audit=restricted
done
