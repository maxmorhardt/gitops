# monitoring

[Grafana `k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) runs Grafana Alloy in each cluster and ships everything to Grafana Cloud, labelled with `cluster` (`dev` or `prod`).

What Alloy collects, and how:

| what | how |
| --- | --- |
| pod and object metrics | `clusterMetrics`: kubelet, cAdvisor, and kube-state-metrics |
| node metrics, including Pi temperatures | `hostMetrics`: node-exporter |
| app, Postgres, Argo CD, Valkey, cert-manager, kured metrics | `prometheusOperatorObjects`: every ServiceMonitor and PodMonitor in the cluster |
| Envoy proxy metrics | `annotationAutodiscovery`, reading the `prometheus.io/*` annotations Envoy Gateway puts on its proxy pods |
| pod logs and Kubernetes events | `podLogsViaLoki`, `clusterEvents` |

## Series budget

The stack is on Grafana Cloud's free tier: 10k active series across both clusters, at one sample per minute each. A series scraped every 30s counts twice, so give ServiceMonitors a 60s interval. Each cluster sends about 3.3k.

Every source keeps only the metrics the rules and dashboards read, listed in [`values.yaml`](values.yaml):

```promql
count by (cluster) ({__name__=~".+"})
```

## Alerts

Every `PrometheusRule` in the cluster is synced to Grafana Cloud's ruler by `alloy-singleton`. The same Application applies everything in [`rules/`](rules/):

- [`workloads.yaml`](rules/workloads.yaml): pods, deployments, statefulsets, daemonsets, jobs, resource overcommit, volumes, and down scrape targets.
- [`nodes.yaml`](rules/nodes.yaml): node readiness and pressure, kubelet health and certificates, and node-exporter's disk, network, clock, and memory alerts.
- [`recording.yaml`](rules/recording.yaml): the three recording rules the alerts read.
- [`platform.yaml`](rules/platform.yaml): certificates, gateway 5xx, Postgres backups, Argo CD, k3s upgrades, `MetricsStopped`, app deployments with no ready pods, Valkey, and Pi temperatures.

Grafana Cloud allows at most 20 rules per group, so split any group that grows past that. The ruler rejects the whole group otherwise.

The first three come from kube-prometheus-stack (originally from the kubernetes and node mixins), copied once with their `job` selectors changed to Alloy's: `integrations/kubernetes/kubelet`, `.../cadvisor`, `.../kube-state-metrics`, and `integrations/node_exporter`. Edit them in place. Groups for things Alloy doesn't scrape on k3s were left out: the API server, scheduler, controller manager, etcd, and kube-state-metrics' own metrics. So were alerts on metrics these clusters never produce: resource quotas, volume usage (local-path doesn't report it), software RAID, and kubelet certificate renewal errors. The CNPG cluster chart's logical replication, disk space, and zone spread alerts are excluded in [`values-cluster.yaml`](../postgres/values-cluster.yaml) for the same reasons.

Each app chart also ships its own rules. Each cluster syncs under its own namespace prefix (`dev`, `prod`) and only queries series with its own `cluster`, so one stack holds both without duplicate alerts.

They evaluate in Grafana Cloud, so routing them to Discord is a one-time setup in the stack: Alerting > Contact points, choose the Grafana Cloud Alertmanager (not Grafana's), add a Discord contact point, and make it the default in its notification policy. The synced rules show under Alerting > Alert rules, as data source-managed rules.

## Dashboards

Dashboard JSON in [`dashboards/`](dashboards/). Import each into Grafana (Dashboards > New > Import); importing a changed file again with the same uid replaces the old one. Each picks its data sources and cluster through variables, and links to the others.

- **[Cluster](dashboards/cluster.json):** health at a glance, nodes (CPU, memory, disk, network, Pi CPU and NVMe temperatures, CPU frequency), CPU and memory by namespace, pods not running and restarts, gateway traffic and errors by route, and Argo CD, Postgres, Valkey, certificates, and kured.
- **[Nodes](dashboards/nodes.json):** one node: CPU by mode, which pods use its CPU and memory, CPU spent outside pods (k3s and the OS), load, pressure, disks, network, and temperatures. The Cluster dashboard's node names link here.
- **[Workloads](dashboards/workloads.json):** one namespace's pods: CPU and memory against requests and limits, throttling, network, restarts, and logs.
- **[Apps](dashboards/apps.json):** one API service's requests, 5xx rate, latency, endpoints, database connections, outbox backlog, and error logs, plus squares activity and the web frontends.

## Uptime

Synthetic Monitoring checks are set up in the stack's UI (Testing & synthetics > Synthetics), with alerting on the check: `https://maxhq.io`, `https://squares.maxhq.io`, `https://api.maxhq.io/squares/stats`, `https://login.maxhq.io/.well-known/openid-configuration`, `https://olympics.maxhq.io`.
