# monitoring

[Grafana `k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) runs Grafana Alloy in each cluster and ships everything to Grafana Cloud, labelled with `cluster: dev` or `cluster: prod`:

| what | how |
| --- | --- |
| node, pod, and object metrics | `clusterMetrics`, with kube-state-metrics and node-exporter deployed alongside |
| app, Postgres, Argo CD, Valkey, sealed-secrets, kured metrics | `prometheusOperatorObjects`: every ServiceMonitor and PodMonitor in the cluster |
| Envoy proxy metrics | `annotationAutodiscovery`, reading the `prometheus.io/*` annotations Envoy Gateway puts on its proxy pods |
| pod logs and Kubernetes events | `podLogsViaLoki`, `clusterEvents` |

Alert rules, the Discord contact point, dashboards, and uptime checks are Terraform in maxhq's `infra/terraform/grafana`, not here.

## Secrets

Two secrets in `monitoring`, one per Grafana Cloud destination, each with `url`, `username`, and `password`. In Grafana Cloud, open the stack's **Prometheus** and **Loki** details for the URL and user (instance id), and create an access policy token with `metrics:write` and `logs:write` for the password:

```bash
scripts/secrets.sh new <cluster> monitoring/grafana-cloud-metrics url=https://prometheus-prod-XX.grafana.net/api/prom/push username=<prometheus user id> password=
scripts/secrets.sh new <cluster> monitoring/grafana-cloud-logs url=https://logs-prod-XXX.grafana.net/loki/api/v1/push username=<loki user id> password=
```

A bare `password=` prompts for the token without echoing it.

## Free tier

Grafana Cloud's free tier allows 10k active series and 50 GB of logs a month across both clusters. If usage gets close, turn off `podLogsViaLoki` in `values-dev.yaml` first.
