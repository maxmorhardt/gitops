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

Every `PrometheusRule` in the cluster becomes a Grafana-managed alert rule. `alloy-singleton` syncs them through Grafana's Prometheus rule conversion API (`/api/convert/prometheus`) into the `repo alerts` folder, one subfolder per PrometheusRule, prefixed with the cluster. They query `grafanacloud-prom` filtered to their own `cluster`, carry a `cluster` label even when the expression aggregates it away, and notify through the notification policy below.

Grafana Cloud's own ruler could evaluate them instead, but this stack has no Cloud Alertmanager behind it, so its alerts would reach nobody.

Give every rule group an `interval`. Grafana stores 1m on a group that has none, so Alloy sees a difference and rewrites the group on every sync.

The same Application applies everything in [`rules/`](rules/):

- [`workloads.yaml`](rules/workloads.yaml): pods, deployments, statefulsets, daemonsets, jobs, resource overcommit, volumes, and down scrape targets.
- [`nodes.yaml`](rules/nodes.yaml): node readiness and pressure, kubelet health and certificates, and node-exporter's disk, network, clock, and memory alerts.
- [`recording.yaml`](rules/recording.yaml): the three recording rules the alerts read.
- [`postgres.yaml`](rules/postgres.yaml): the CloudNativePG cluster chart's alerts that work here, copied because the chart's own group can't set an interval.
- [`platform.yaml`](rules/platform.yaml): certificates, gateway 5xx, Postgres backups, Argo CD, k3s upgrades, `MetricsStopped`, app deployments with no ready pods, Valkey, and Pi temperatures.

Grafana Cloud allows at most 20 rules per group, so split any group that grows past that. The ruler rejects the whole group otherwise.

### Set up by hand in Grafana

These live in the stack's UI rather than in git, so a new stack needs them recreated:

- **Rule sync**: the `repo alerts` folder (uid `repo-alerts`), and a service account `alloy-rules` with the Admin role. Its token is the sealed `monitoring/grafana-rules` secret in each cluster.

- **Notification routing**, in Alerting > Notification configuration:
  - Contact point `alerts`, a Telegram integration with the `@maxhqio_bot` bot token and chat ID `8753214944`.
  - Default notification policy: sends to `alerts`, grouped by `alertname` and `cluster`.
  - A child route `severity = info` that sends to `empty`, a contact point with no integrations, which silences info alerts.

  Alertmanager retries at each group interval until Telegram gets through.
- **Series limit alert**, `Metrics near free tier limit`: `max(grafanacloud_instance_active_series)` on the `grafanacloud-usage` data source, above 9000 for 15m, with `severity=warning`. It lives in the `maxhq` folder, `usage` group, evaluated every 5m. It can't live in `rules/`, because synced rules only query the metrics data source.
- **Postgres data source** (prod only), for the Contests dashboard:
  - Private data source connect network `pdc-maxhqio-default` and its signing token `prod`, sealed as `monitoring/pdc-agent` (key `token`). [`pdc/pdc-agent.yaml`](pdc/pdc-agent.yaml) runs the agent in prod; it only forwards to `postgres-cluster-ro`.
  - A PostgreSQL data source whose name contains `postgres`: host `postgres-cluster-ro.cnpg-database.svc.cluster.local:5432`, database `squares`, user `grafana` with the password from `scripts/secrets.sh get prod cnpg-database/postgres-grafana-user password`, TLS `require`, version 15+, max open connections 5, and the PDC network above. The role and its grants are in [postgres/README.md](../postgres/README.md).

## Dashboards

- **[Cluster](dashboards/cluster.json):** health at a glance, nodes (CPU, memory, disk, network, Pi CPU and NVMe temperatures, CPU frequency), CPU and memory by namespace, pods not running and restarts, gateway traffic and errors by route, and Argo CD, Postgres, Valkey, certificates, and kured.
- **[Nodes](dashboards/nodes.json):** one node: CPU by mode, which pods use its CPU and memory, CPU spent outside pods (k3s and the OS), load, pressure, disks, network, and temperatures. The Cluster dashboard's node names link here.
- **[Workloads](dashboards/workloads.json):** one namespace's pods: CPU and memory against requests and limits, throttling, network, restarts, and logs.
- **[Apps](dashboards/apps.json):** every API service at a glance, then one service's requests, 5xx rate, mean latency, endpoints, database pool, outbox lag, and error and warning logs, plus squares activity and realtime streams. Latency is the mean from the histogram's sum and count, since the series budget leaves too few buckets for useful percentiles.
- **[Users](dashboards/users.json):** daily and hourly active users, who they are, where they are (country, region, city, IP), Dex logins, and ad visitors. Every panel queries Loki: the API services' `request` log line (with `user`, `client_ip`, and Cloudflare's `cf_country`, `cf_region`, and `cf_city`), Dex's `login successful` line, and the squares web server's access log, where an ad click id (`gclid`, `gbraid`, `wbraid`, `fbclid`) shows up in the landing request or, when Cloudflare served the page from cache, in the referer of its favicon requests. That keeps it off the series budget, and logs are kept 14 days.
- **[Contests](dashboards/contests.json):** every squares contest with its owner, game, kickoff, players, and squares; every user with what they own, joined, and claimed; a timeline of what each user did; and one contest's players and squares. Every query sticks to tables and columns that survive maxhq#208's invite rework. It queries the Postgres replica, so it shows what the database holds now: a square claimed and later cleared doesn't appear, though the Users dashboard's request logs have it. `User (regex)` matches the Users dashboard's, so the links between them keep the filter; set `Hide users` to your own accounts and save the dashboard to leave test contests out.

## Uptime

Synthetic Monitoring checks are set up in the stack's UI (Testing & synthetics > Synthetics), with alerting on the check: `https://maxhq.io`, `https://squares.maxhq.io`, `https://api.maxhq.io/squares/stats`, `https://login.maxhq.io/.well-known/openid-configuration`, `https://olympics.maxhq.io`.
