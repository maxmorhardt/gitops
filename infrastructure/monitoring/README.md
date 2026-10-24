# monitoring

[Grafana `k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) runs Grafana Alloy in each cluster and ships everything to Grafana Cloud, labelled with `cluster` (`dev` or `prod`).

What Alloy collects, and how:

| what | how |
| --- | --- |
| pod and object metrics | `clusterMetrics`: kubelet, cAdvisor, and kube-state-metrics |
| node metrics | `hostMetrics`: node-exporter |
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

### Set up by hand in Grafana

Two pieces live in the stack's UI rather than in git, so a new stack needs them recreated:

- **Notification routing**, in Alerting > Notification configuration:
  - Contact point `alerts`, with two integrations that both fire on every alert:
    - Discord, with the alerts channel's webhook URL, using Discord's webhook username and showing the message in an embed;
    - email, as the backup.
  - Default notification policy: sends to `alerts`, grouped by `alertname` and `cluster`.
  - A child route `severity = info` that sends to `empty`, a contact point with no integrations, which silences info alerts.

  Discord sometimes rate-limits Grafana Cloud's shared IPs (a 429 on the contact point test), which is why email is there too. Alertmanager also retries at each group interval until Discord gets through.
- **Series limit alert**, `Metrics near free tier limit`: `max(grafanacloud_instance_active_series)` on the `grafanacloud-usage` data source, above 9000 for 15m, with `severity=warning`. It lives in the `maxhq` folder, `usage` group, evaluated every 5m. It can't live in `rules/`, because the ruler can't query the usage data source.

## Dashboards

- **[Cluster](dashboards/cluster.json):** health at a glance, nodes (CPU, memory, disk, network, Pi CPU and NVMe temperatures, CPU frequency), CPU and memory by namespace, pods not running and restarts, gateway traffic and errors by route, and Argo CD, Postgres, Valkey, certificates, and kured.
- **[Nodes](dashboards/nodes.json):** one node: CPU by mode, which pods use its CPU and memory, CPU spent outside pods (k3s and the OS), load, pressure, disks, network, and temperatures. The Cluster dashboard's node names link here.
- **[Workloads](dashboards/workloads.json):** one namespace's pods: CPU and memory against requests and limits, throttling, network, restarts, and logs.
- **[Apps](dashboards/apps.json):** one API service's requests, 5xx rate, latency, endpoints, database connections, outbox backlog, and error logs, plus squares activity and the web frontends.

## Uptime

Synthetic Monitoring checks are set up in the stack's UI (Testing & synthetics > Synthetics), with alerting on the check: `https://maxhq.io`, `https://squares.maxhq.io`, `https://api.maxhq.io/squares/stats`, `https://login.maxhq.io/.well-known/openid-configuration`, `https://olympics.maxhq.io`.
