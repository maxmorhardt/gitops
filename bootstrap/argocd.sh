#!/usr/bin/env bash
set -euo pipefail

cluster="${1:?usage: bootstrap/argocd.sh <dev|prod>}"
cd "$(dirname "$0")/.."

values=(--values infrastructure/argocd/values.yaml)
[ -f "infrastructure/argocd/values-$cluster.yaml" ] && values+=(--values "infrastructure/argocd/values-$cluster.yaml")

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
helm upgrade argocd argo/argo-cd \
	--version 10.10.3 \
	--install \
	--wait \
	--timeout 10m \
	--namespace argocd \
	--create-namespace \
	"${values[@]}"

kubectl apply -f "clusters/$cluster/root.yaml"

echo
echo "admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
