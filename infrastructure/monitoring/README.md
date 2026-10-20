# monitoring

[Grafana `k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) runs Grafana Alloy in each cluster and ships everything to Grafana Cloud, labelled with `cluster: dev` or `cluster: prod`:

| what | how |
| --- | --- |
| node, pod, and object metrics | `clusterMetrics`, with kube-state-metrics and node-exporter deployed alongside |
| app, Postgres, Argo CD, Valkey, sealed-secrets, kured metrics | `prometheusOperatorObjects`: every ServiceMonitor and PodMonitor in the cluster |
| Envoy proxy metrics | `annotationAutodiscovery`, reading the `prometheus.io/*` annotations Envoy Gateway puts on its proxy pods |
| pod logs and Kubernetes events | `podLogsViaLoki`, `clusterEvents` |

## Alerts

Every `PrometheusRule` in the cluster is synced to Grafana Cloud's ruler by `alloy-singleton`: each app chart's own rules, plus the platform rules in [`rules/platform.yaml`](rules/platform.yaml) (nodes, crash loops, disk, certificates, gateway 5xx, Postgres backups, Argo CD), which the same Application applies. Each cluster syncs under its own namespace prefix (`dev`, `prod`) and only queries its own `cluster` series, so one stack holds both without duplicate alerts.

They evaluate in Grafana Cloud, so routing them to Discord is a one-time setup in the stack: Alerting > Contact points, choose the Grafana Cloud Alertmanager (not Grafana's), add a Discord contact point, and make it the default in its notification policy. The synced rules show under Alerting > Alert rules, as data source-managed rules.

## Dashboards

App dashboards are JSON in [`dashboards/`](dashboards/README.md). Grafana Cloud's Kubernetes Monitoring app covers the cluster itself.

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

Grafana Cloud's free tier allows 10k active series and 50 GB of logs a month across both clusters. If usage gets close, turn off `podLogsViaLoki` in `values-dev.yaml` first.
