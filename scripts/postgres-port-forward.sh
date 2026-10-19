#!/usr/bin/env bash
set -euo pipefail

cluster="${1:?usage: scripts/postgres-port-forward.sh <cluster> [local-port]}"
port="${2:-5433}"

while true; do
	kubectl --context "$cluster" port-forward -n cnpg-database svc/postgres-cluster-rw "$port:5432" || sleep 2
done
