#!/usr/bin/env bash
set -euo pipefail

version=92.11.0

cd "$(dirname "$0")/.."
dir=infrastructure/monitoring
rules=$dir/rules/kube-prometheus.yaml
dashboards=$dir/dashboards/kubernetes

# alloy names its jobs after grafana's integrations, and scrapes cadvisor as its own job
relabel() {
	sed -E \
		-e 's#job=(\\?)"kubelet\1", *metrics_path=\1"/metrics/cadvisor\1"#job=\1"integrations/kubernetes/cadvisor\1"#g' \
		-e 's#job=(\\?)"kubelet\1", *metrics_path=\1"/metrics\1"#job=\1"integrations/kubernetes/kubelet\1"#g' \
		-e 's#job=(\\?)"kubelet\1"#job=\1"integrations/kubernetes/kubelet\1"#g' \
		-e 's#, *metrics_path=(\\?)"/metrics\1"##g' \
		-e 's#job=(\\?)"kube-state-metrics\1"#job=\1"integrations/kubernetes/kube-state-metrics\1"#g' \
		-e 's#job=(\\?)"node-exporter\1"#job=\1"integrations/node_exporter\1"#g'
}

rendered=$(helm template kube-prometheus kube-prometheus-stack \
	--repo https://prometheus-community.github.io/helm-charts --version "$version" \
	--namespace monitoring -f "$dir/kube-prometheus/values.yaml" | relabel)

echo "$rendered" | yq 'select(.kind == "PrometheusRule") | del(.metadata.labels, .metadata.annotations)' >"$rules"

rm -rf "$dashboards"
mkdir -p "$dashboards"
for name in $(echo "$rendered" | yq 'select(.kind == "ConfigMap" and .metadata.labels.grafana_dashboard == "1") | .data | keys | .[]'); do
	case "$name" in grafana-overview.json | prometheus.json) continue ;; esac
	echo "$rendered" | N="$name" yq 'select(.kind == "ConfigMap") | .data[strenv(N)] | select(. != null)' | jq . >"$dashboards/$name"
done

echo "wrote $rules and $(ls "$dashboards" | wc -l) dashboards to $dashboards/"
