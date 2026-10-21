# monitoring

[Grafana `k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) runs Grafana Alloy in each cluster and ships everything to Grafana Cloud, labelled with `k8s_cluster_name` and `cluster` (`dev` or `prod`).

What Alloy collects, and how:

| what | how |
| --- | --- |
| pod and object metrics | `clusterMetrics`: kubelet, cAdvisor, and kube-state-metrics |
| node metrics | `hostMetrics`: node-exporter |
| app, Postgres, Argo CD, Valkey, sealed-secrets, kured metrics | `prometheusOperatorObjects`: every ServiceMonitor and PodMonitor in the cluster |
| Envoy proxy metrics | `annotationAutodiscovery`, reading the `prometheus.io/*` annotations Envoy Gateway puts on its proxy pods |
| pod logs and Kubernetes events | `podLogsViaLoki`, `clusterEvents` |

## Alerts

Every `PrometheusRule` in the cluster is synced to Grafana Cloud's ruler by `alloy-singleton`. The same Application applies everything in [`rules/`](rules/):

- [`workloads.yaml`](rules/workloads.yaml): pods, deployments, statefulsets, daemonsets, jobs, resource overcommit, volumes, and down scrape targets.
- [`nodes.yaml`](rules/nodes.yaml): node readiness and pressure, kubelet health and certificates, and node-exporter's disk, network, clock, and memory alerts.
- [`recording.yaml`](rules/recording.yaml): the recording rules the alerts and the kubernetes dashboards read.
- [`platform.yaml`](rules/platform.yaml): certificates, gateway 5xx, Postgres backups, Argo CD, k3s upgrades, and `MetricsStopped`.

Grafana Cloud allows at most 20 rules per group, so split any group that grows past that. The ruler rejects the whole group otherwise.

The first three come from kube-prometheus-stack (originally from the kubernetes and node mixins), copied once with their `job` selectors changed to Alloy's: `integrations/kubernetes/kubelet`, `.../cadvisor`, `.../kube-state-metrics`, and `integrations/node_exporter`. Edit them in place. Groups for things Alloy doesn't scrape on k3s were left out: the API server, scheduler, controller manager, etcd, and kube-state-metrics' own metrics.

The extra metrics these rules read, beyond Grafana's default allowlists, are listed under `includeMetrics` in [`values.yaml`](values.yaml).

Each app chart also ships its own rules. Each cluster syncs under its own namespace prefix (`dev`, `prod`) and only queries series with its own `k8s_cluster_name`, so one stack holds both without duplicate alerts.

They evaluate in Grafana Cloud, so routing them to Discord is a one-time setup in the stack: Alerting > Contact points, choose the Grafana Cloud Alertmanager (not Grafana's), add a Discord contact point, and make it the default in its notification policy. The synced rules show under Alerting > Alert rules, as data source-managed rules.

## Dashboards

Dashboard JSON in [`dashboards/`](dashboards/), one folder per type; import each folder into a Grafana folder of the same name:

- **[`kubernetes/`](dashboards/kubernetes/):** compute resources by cluster, namespace, node, workload, and pod, persistent volumes, and Node Exporter Full for each node.
- **[`platform/`](dashboards/platform/):** Argo CD, CloudNativePG, kured, sealed-secrets, Valkey, and NGINX (the web frontends' nginx exporter sidecars).
- **[`squares/`](dashboards/squares/):** one per squares service.

Each dashboard picks its data source through a variable. Dev and prod share one stack, so each dashboard also selects a cluster.

## Uptime

Synthetic Monitoring checks are set up in the stack's UI (Testing & synthetics > Synthetics), with alerting on the check: `https://maxhq.io`, `https://squares.maxhq.io`, `https://api.maxhq.io/squares/stats`, `https://login.maxhq.io/.well-known/openid-configuration`, `https://olympics.maxhq.io`.

