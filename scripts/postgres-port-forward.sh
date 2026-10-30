#!/usr/bin/env bash
set -euo pipefail

cluster="${1:-}"
case "$cluster" in
dev) port=5433 ;;
prod) port=5434 ;;
*) echo "usage: scripts/postgres-port-forward.sh <dev|prod>" >&2; exit 1 ;;
esac

while true; do
	kubectl --context "$cluster" port-forward -n cnpg-database svc/postgres-cluster-rw "$port:5432" || sleep 2
done
