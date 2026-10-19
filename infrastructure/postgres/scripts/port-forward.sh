while true; do
    kubectl port-forward -n cnpg-database svc/postgres-cluster-rw 5433:5432
done