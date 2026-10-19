#!/usr/bin/env bash
set -euo pipefail

cluster="${1:?usage: scripts/postgres-restore.sh <cluster> <file>}"
file="${2:?usage: scripts/postgres-restore.sh <cluster> <file>}"

pod=$(kubectl --context "$cluster" get pod -n cnpg-database \
	-l cnpg.io/instanceRole=primary,cnpg.io/cluster=postgres-cluster -o jsonpath='{.items[0].metadata.name}')

read -r -p "restore $file into $cluster ($pod)? [y/N] " answer
[ "$answer" = y ] || exit 1

kubectl --context "$cluster" cp "$file" "cnpg-database/$pod:/var/lib/postgresql/data/restore.sql" -c postgres
kubectl --context "$cluster" exec -n cnpg-database "$pod" -c postgres -- \
	sh -c 'psql -U postgres -f /var/lib/postgresql/data/restore.sql; rm -f /var/lib/postgresql/data/restore.sql'
