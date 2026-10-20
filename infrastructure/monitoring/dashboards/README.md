# dashboards

Grafana dashboards for the apps, kept here rather than in their Helm charts: Grafana Cloud does not read in-cluster ConfigMaps. Each picks its data sources through `prometheus_datasource` and `loki_datasource` variables, so the same JSON works in any stack.

To load them, either import each file once (Dashboards > New > Import), or point Grafana's Git Sync at this folder so edits in git show up in Grafana and saves in Grafana come back as pull requests.

Cluster and node dashboards come with Grafana Cloud's Kubernetes Monitoring app, which reads what Alloy ships.
