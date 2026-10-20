#!/usr/bin/env bash
set -euo pipefail

cluster="${1:?usage: scripts/postgres-dumpall.sh <cluster> [file]}"
file="${2:-postgres-dumpall-$cluster.sql}"

pod=$(kubectl --context "$cluster" get pod -n cnpg-database \
	-l cnpg.io/instanceRole=primary,cnpg.io/cluster=postgres-cluster -o jsonpath='{.items[0].metadata.name}')

echo "dumping every database from $cluster ($pod) to $file"
kubectl --context "$cluster" exec -n cnpg-database "$pod" -c postgres -- pg_dumpall -U postgres >"$file"
