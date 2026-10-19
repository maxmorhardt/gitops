#!/usr/bin/env bash
# seals every secret a cluster needs
set -euo pipefail

cluster="${1:?usage: bootstrap/seal-secrets.sh <dev|prod> <env-file>}"
env_file="${2:?usage: bootstrap/seal-secrets.sh <dev|prod> <env-file>}"
cd "$(dirname "$0")/.."

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

cert="clusters/$cluster/pub-cert.pem"
out="clusters/$cluster/secrets"

if [ ! -f "$cert" ]; then
	kubeseal --context "$cluster" --controller-name sealed-secrets --controller-namespace sealed-secrets \
		--fetch-cert >"$cert"
fi

require() {
	local missing=()
	for name in "$@"; do
		[ -n "${!name:-}" ] || missing+=("$name")
	done
	if [ ${#missing[@]} -gt 0 ]; then
		echo "missing in $env_file: ${missing[*]}" >&2
		exit 1
	fi
}

# seal <namespace> <name> <kubectl create secret args...>
seal() {
	local namespace="$1" name="$2"
	shift 2
	mkdir -p "$out/$namespace"
	kubectl create secret "$@" --namespace "$namespace" --dry-run=client -o yaml \
		| kubeseal --format yaml --cert "$cert" >"$out/$namespace/$name.yaml"
	echo "sealed $namespace/$name"
}

require POSTGRES_SUPERUSER_PASSWORD POSTGRES_ADMIN_PASSWORD DEX_POSTGRES_PASSWORD \
	GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET \
	ARGOCD_CLIENT_SECRET AGES_CLIENT_SECRET VALKEY_DEFAULT_PASSWORD VALKEY_SQUARES_PASSWORD \
	KURED_DISCORD_URL INTERNAL_API_TOKEN SMTP_USER SMTP_PASSWORD TURNSTILE_SECRET_KEY \
	OLYMPICS_POSTGRES_PASSWORD OLYMPICS_ADMIN_EMAILS AGES_TO_EMAILS \
	DOCKER_PULL_TOKEN MAXHQ_PRIVATE_DEPLOY_KEY

domain=$([ "$cluster" = prod ] && echo maxhq.io || echo dev.maxhq.io)
origin="https://squares.$domain"

seal cnpg-database postgres-superuser generic postgres-superuser --type=kubernetes.io/basic-auth \
	--from-literal=username=postgres --from-literal=password="$POSTGRES_SUPERUSER_PASSWORD"
seal cnpg-database postgres-admin-user generic postgres-admin-user --type=kubernetes.io/basic-auth \
	--from-literal=username=maxmorhardt --from-literal=password="$POSTGRES_ADMIN_PASSWORD"
seal cnpg-database postgres-dex-user generic postgres-dex-user --type=kubernetes.io/basic-auth \
	--from-literal=username=dex --from-literal=password="$DEX_POSTGRES_PASSWORD"
seal cnpg-database postgres-olympics-user generic postgres-olympics-user --type=kubernetes.io/basic-auth \
	--from-literal=username=olympics --from-literal=password="$OLYMPICS_POSTGRES_PASSWORD"

seal dex dex-env generic dex-env \
	--from-literal=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" --from-literal=GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
	--from-literal=GITHUB_CLIENT_ID="$GITHUB_CLIENT_ID" --from-literal=GITHUB_CLIENT_SECRET="$GITHUB_CLIENT_SECRET" \
	--from-literal=DEX_POSTGRES_PASSWORD="$DEX_POSTGRES_PASSWORD" \
	--from-literal=ARGOCD_CLIENT_SECRET="$ARGOCD_CLIENT_SECRET" --from-literal=AGES_CLIENT_SECRET="$AGES_CLIENT_SECRET"

# Argo CD only resolves $secret:key references in secrets labelled part-of=argocd
mkdir -p "$out/argocd"
kubectl create secret generic argocd-oidc --namespace argocd --dry-run=client -o yaml \
	--from-literal=clientSecret="$ARGOCD_CLIENT_SECRET" \
	| kubectl label --local -f - app.kubernetes.io/part-of=argocd -o yaml \
	| kubeseal --format yaml --cert "$cert" >"$out/argocd/argocd-oidc.yaml"
echo "sealed argocd/argocd-oidc"

kubectl create secret generic repo-maxhq-private --namespace argocd --dry-run=client -o yaml \
	--from-literal=type=git --from-literal=url=git@github.com:maxmorhardt/maxhq-private.git \
	--from-file=sshPrivateKey="$MAXHQ_PRIVATE_DEPLOY_KEY" \
	| kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
	| kubeseal --format yaml --cert "$cert" >"$out/argocd/repo-maxhq-private.yaml"
echo "sealed argocd/repo-maxhq-private"

seal valkey valkey-users generic valkey-users \
	--from-literal=default="$VALKEY_DEFAULT_PASSWORD" --from-literal=squares="$VALKEY_SQUARES_PASSWORD"
seal kube-system kured-discord generic kured-discord --from-literal=url="$KURED_DISCORD_URL"

db=(
	--from-literal=DB_HOST=postgres-cluster-rw.cnpg-database.svc.cluster.local --from-literal=DB_PORT=5432
	--from-literal=DB_NAME=maxhq --from-literal=DB_USER=maxmorhardt
	--from-literal=DB_PASSWORD="$POSTGRES_ADMIN_PASSWORD" --from-literal=DB_SSL_MODE=require
	--from-literal=DB_READ_HOST=postgres-cluster-ro.cnpg-database.svc.cluster.local --from-literal=DB_READ_PORT=5432
	--from-literal=DB_READ_NAME=maxhq --from-literal=DB_READ_USER=maxmorhardt
	--from-literal=DB_READ_PASSWORD="$POSTGRES_ADMIN_PASSWORD" --from-literal=DB_READ_SSL_MODE=require
)
shared=(
	--from-literal=ALLOWED_ORIGINS="$origin"
	--from-literal=REDIS_URL="redis://squares:$VALKEY_SQUARES_PASSWORD@valkey-master.valkey.svc:6379/0"
)
if [ "$cluster" = dev ]; then
	db+=(--from-literal=DB_MAX_OPEN_CONNS=5 --from-literal=DB_MAX_IDLE_CONNS=2)
fi

seal squares squares-contests-env generic squares-contests-env "${db[@]}" "${shared[@]}" \
	--from-literal=INTERNAL_API_TOKEN="$INTERNAL_API_TOKEN"
seal squares squares-games-env generic squares-games-env "${db[@]}" "${shared[@]}"
seal squares squares-realtime-env generic squares-realtime-env "${shared[@]}" \
	--from-literal=INTERNAL_API_TOKEN="$INTERNAL_API_TOKEN"
seal squares squares-accounts-env generic squares-accounts-env "${db[@]}" "${shared[@]}" \
	--from-literal=INTERNAL_API_TOKEN="$INTERNAL_API_TOKEN" \
	--from-literal=SMTP_HOST=smtp.zoho.com --from-literal=SMTP_PORT=587 \
	--from-literal=SMTP_USER="$SMTP_USER" --from-literal=SMTP_PASSWORD="$SMTP_PASSWORD" \
	--from-literal=SUPPORT_EMAIL=support@maxhq.io --from-literal=TURNSTILE_SECRET_KEY="$TURNSTILE_SECRET_KEY"

seal olympics olympics-api-env generic olympics-api-env \
	--from-literal=DB_HOST=postgres-cluster-rw.cnpg-database.svc.cluster.local --from-literal=DB_PORT=5432 \
	--from-literal=DB_NAME=olympics --from-literal=DB_USER=olympics \
	--from-literal=DB_PASSWORD="$OLYMPICS_POSTGRES_PASSWORD" --from-literal=DB_SSL_MODE=require \
	--from-literal=OIDC_CLIENT_ID=olympics --from-literal=OIDC_ISSUER="https://login.$domain" \
	--from-literal=ALLOWED_ORIGINS="https://olympics.$domain" --from-literal=ADMIN_EMAILS="$OLYMPICS_ADMIN_EMAILS"

seal ages docker-secret docker-registry docker-secret --docker-server=https://index.docker.io/v1/ \
	--docker-username=maxmorhardt --docker-password="$DOCKER_PULL_TOKEN"
seal ages ages-oidc-client generic ages-oidc-client \
	--from-literal=client-secret="$AGES_CLIENT_SECRET"
seal ages ages-email-env generic ages-email-env \
	--from-literal=SMTP_SERVER=smtp.zoho.com --from-literal=SMTP_PORT=587 \
	--from-literal=SMTP_USERNAME="$SMTP_USER" --from-literal=SMTP_PASSWORD="$SMTP_PASSWORD" \
	--from-literal=FROM_EMAIL="$SMTP_USER" --from-literal=TO_EMAILS="$AGES_TO_EMAILS"

if [ "$cluster" = prod ]; then
	require AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY ORIGIN_CERT ORIGIN_KEY
	seal cnpg-database aws-s3-credentials generic aws-s3-credentials \
		--from-literal=ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" --from-literal=ACCESS_SECRET_KEY="$AWS_SECRET_ACCESS_KEY"
	seal envoy-gateway-system maxhq.io-tls tls maxhq.io-tls --cert="$ORIGIN_CERT" --key="$ORIGIN_KEY"
else
	require CLOUDFLARE_DNS_TOKEN
	seal cert-manager cloudflare-api-token generic cloudflare-api-token --from-literal=api-token="$CLOUDFLARE_DNS_TOKEN"
fi
