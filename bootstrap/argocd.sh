#!/usr/bin/env bash
set -euo pipefail

cluster="${1:?usage: bootstrap/argocd.sh <dev|prod>}"
cd "$(dirname "$0")/.."

# dev values added if thats the cluster env
values=(--values infrastructure/argocd/values.yaml)
[ -f "infrastructure/argocd/values-$cluster.yaml" ] && values+=(--values "infrastructure/argocd/values-$cluster.yaml")

# install without crds first if not installed
if ! kubectl get crd httproutes.gateway.networking.k8s.io servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
	for component in controller repoServer server redis; do
		values+=(--set "$component.metrics.serviceMonitor.enabled=false")
	done

	values+=(--set server.httproute.enabled=false)
fi

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
helm upgrade argocd argo/argo-cd \
	--version 10.11.1 \
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
