DUMP_FILE="postgres-dumpall.sql"
NAMESPACE="cnpg-database"

POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/instanceRole=primary,cnpg.io/cluster=postgres-cluster" -o jsonpath='{.items[0].metadata.name}')

echo "Dumping all databases from PostgreSQL cluster (pod: $POD_NAME)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -c postgres -- pg_dumpall -U postgres > "$DUMP_FILE"

echo "Dump complete! Saved to $DUMP_FILE"
