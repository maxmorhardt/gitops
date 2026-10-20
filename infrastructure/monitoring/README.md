# monitoring

[Grafana `k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) runs Grafana Alloy in each cluster and ships everything to Grafana Cloud, labelled with `cluster: dev` or `cluster: prod`:

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
- [`platform.yaml`](rules/platform.yaml): certificates, gateway 5xx, Postgres backups, Argo CD, and k3s upgrades.

The first three come from kube-prometheus-stack (originally from the kubernetes and node mixins), copied once with their `job` selectors changed to Alloy's: `integrations/kubernetes/kubelet`, `.../cadvisor`, `.../kube-state-metrics`, and `integrations/node_exporter`. Edit them in place. Groups for things Alloy doesn't scrape on k3s were left out: the API server, scheduler, controller manager, etcd, and kube-state-metrics' own metrics.

The extra metrics these rules read, beyond Grafana's default allowlists, are listed under `includeMetrics` in [`values.yaml`](values.yaml).

Each app chart also ships its own rules. Each cluster syncs under its own namespace prefix (`dev`, `prod`) and only queries its own `cluster` series, so one stack holds both without duplicate alerts.

They evaluate in Grafana Cloud, so routing them to Discord is a one-time setup in the stack: Alerting > Contact points, choose the Grafana Cloud Alertmanager (not Grafana's), add a Discord contact point, and make it the default in its notification policy. The synced rules show under Alerting > Alert rules, as data source-managed rules.

## Dashboards

Dashboard JSON in [`dashboards/`](dashboards/), one folder per type; import each folder into a Grafana folder of the same name:

- **[`kubernetes/`](dashboards/kubernetes/):** compute resources by cluster, namespace, node, workload, and pod, persistent volumes, and Node Exporter Full for each node.
- **[`platform/`](dashboards/platform/):** Argo CD, kured, sealed-secrets, and Valkey.
- **[`squares/`](dashboards/squares/):** one per squares service.

Each dashboard picks its data source through a variable. Dev and prod share one stack, so each dashboard also selects a cluster. Most have a `cluster` variable. The platform dashboards and Node Exporter Full have a `Filters` bar instead, which defaults to `cluster = prod`.

To load them, import each file once (Dashboards > New > Import), or point Grafana's Git Sync at the folder.

Node Exporter Full has panels for metrics outside the allowlist, such as pressure, schedstat, and the full network detail, and those panels stay empty.

## Uptime

Synthetic Monitoring checks are set up in the stack's UI (Testing & synthetics > Synthetics), with alerting on the check: `https://maxhq.io`, `https://squares.maxhq.io`, `https://api.maxhq.io/squares/stats`, `https://login.maxhq.io/.well-known/openid-configuration`, `https://olympics.maxhq.io`.

## Secrets

Two secrets in `monitoring`, one per Grafana Cloud destination, each with `url`, `username`, and `password`. In Grafana Cloud, open the stack's **Prometheus** and **Loki** details for the URL and user (instance id), and create an access policy token with `metrics:write`, `logs:write`, `rules:read`, and `rules:write` for the password:

```bash
scripts/secrets.sh new <cluster> monitoring/grafana-cloud-metrics url=https://prometheus-prod-XX.grafana.net/api/prom/push username=<prometheus user id> password=
scripts/secrets.sh new <cluster> monitoring/grafana-cloud-logs url=https://logs-prod-XXX.grafana.net/loki/api/v1/push username=<loki user id> password=
```

A bare `password=` prompts for the token without echoing it.

## Free tier

Grafana Cloud's free tier allows 10k active series and 50 GB of logs a month across both clusters. Metric series are the tight one. Check usage under Administration > Cost management after the first day.

If usage gets close:

1. Turn off `podLogsViaLoki` in `values-dev.yaml`.
2. Trim the `includeMetrics` lists.
3. Drop dev's node metrics (`hostMetrics.enabled: false` in `values-dev.yaml`).

Pod veth interfaces are already dropped from the node network metrics.
