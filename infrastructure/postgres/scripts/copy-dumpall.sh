DUMP_FILE="postgres-dumpall.sql"
NAMESPACE="cnpg-database"

POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/instanceRole=primary,cnpg.io/cluster=postgres-cluster" -o jsonpath='{.items[0].metadata.name}')

echo "Copying dump file to pod ($POD_NAME)..."
kubectl cp "$DUMP_FILE" "$NAMESPACE/$POD_NAME:/var/lib/postgresql/data/restore.sql" -c postgres

echo "Copy complete!"

echo -e "\nRun the following in the pod:"
echo "psql -U postgres -f /var/lib/postgresql/data/restore.sql"
echo "rm -f /var/lib/postgresql/data/restore.sql"