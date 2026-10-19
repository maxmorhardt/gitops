#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage:
  scripts/secrets.sh unseal <cluster> <scope> [--key <sealing-key.yaml>]
  scripts/secrets.sh seal   <cluster> <scope>
  scripts/secrets.sh new    <cluster> --secret <namespace>/<name>
  scripts/secrets.sh clean

scope: --all | --namespace <namespace> | --secret <namespace>/<name>

  unseal  write each sealed secret as a plain Secret to .secrets/<cluster>/<namespace>/<name>.yaml,
          read from the live cluster, or offline from a sealing key backup with --key
  seal    encrypt .secrets/<cluster>/... into clusters/<cluster>/secrets/... to commit
  new     start .secrets/<cluster>/<namespace>/<name>.yaml for a secret that doesn't exist yet
  clean   delete .secrets/
EOF
	exit 1
}

cd "$(dirname "$0")/.."
plain_root=.secrets

command="${1:-}"
[ -n "$command" ] || usage
shift

if [ "$command" = clean ]; then
	rm -rf "$plain_root"
	echo "deleted $plain_root/"
	exit 0
fi

cluster="${1:-}"
[ -n "$cluster" ] && [ -d "clusters/$cluster" ] || usage
shift

scope=""
key=""
while [ $# -gt 0 ]; do
	case "$1" in
	--all) scope=all ;;
	--namespace) scope="ns:${2:?--namespace needs a value}"; shift ;;
	--secret) scope="secret:${2:?--secret needs <namespace>/<name>}"; shift ;;
	--key) key="${2:?--key needs a file}"; shift ;;
	*) usage ;;
	esac
	shift
done
[ -n "$scope" ] || usage

sealed_dir="clusters/$cluster/secrets"
plain_dir="$plain_root/$cluster"
cert="clusters/$cluster/pub-cert.pem"

# files under <root> matching the scope, as <namespace>/<name>
matching() {
	local root="$1"
	[ -d "$root" ] || return 0
	(cd "$root" && find . -mindepth 2 -maxdepth 2 -name '*.yaml' | sed 's#^\./##; s#\.yaml$##' | sort) |
		while read -r ref; do
			case "$scope" in
			all) echo "$ref" ;;
			ns:*) [ "${ref%%/*}" = "${scope#ns:}" ] && echo "$ref" || true ;;
			secret:*) [ "$ref" = "${scope#secret:}" ] && echo "$ref" || true ;;
			esac
		done
}

# a Secret as readable YAML: values decoded into stringData, cluster bookkeeping dropped
readable() {
	jq '{
		apiVersion: "v1",
		kind: "Secret",
		type: (.type // "Opaque"),
		metadata: ({name: .metadata.name, namespace: .metadata.namespace}
			+ (if (.metadata.labels // {}) == {} then {} else {labels: .metadata.labels} end)),
		stringData: ((.data // {}) | map_values(@base64d))
	}' | yq -P '.' | tr -d '\r'
}

unseal() {
	local refs
	refs=$(matching "$sealed_dir")
	[ -n "$refs" ] || { echo "no sealed secrets match" >&2; exit 1; }
	for ref in $refs; do
		local ns="${ref%%/*}" name="${ref#*/}" out="$plain_dir/$ref.yaml"
		mkdir -p "$(dirname "$out")"
		if [ -n "$key" ]; then
			kubeseal --recovery-unseal --recovery-private-key "$key" -o json <"$sealed_dir/$ref.yaml"
		else
			kubectl --context "$cluster" get secret "$name" -n "$ns" -o json
		fi | readable >"$out"
		echo "unsealed $ref -> $out"
	done
}

seal() {
	local refs
	refs=$(matching "$plain_dir")
	[ -n "$refs" ] || { echo "nothing in $plain_dir matches; unseal or new first" >&2; exit 1; }
	if [ ! -f "$cert" ]; then
		kubeseal --context "$cluster" --controller-name sealed-secrets --controller-namespace sealed-secrets \
			--fetch-cert >"$cert"
	fi
	for ref in $refs; do
		local ns="${ref%%/*}" name="${ref#*/}" in="$plain_dir/$ref.yaml"
		if [ "$(yq '.metadata.namespace' "$in")" != "$ns" ] || [ "$(yq '.metadata.name' "$in")" != "$name" ]; then
			echo "$in: metadata.namespace/name must be $ns/$name" >&2
			exit 1
		fi
		mkdir -p "$sealed_dir/$ns"
		kubeseal --format yaml --cert "$cert" <"$in" >"$sealed_dir/$ref.yaml"
		echo "sealed $in -> $sealed_dir/$ref.yaml"
	done
}

new() {
	case "$scope" in secret:*/*) ;; *) usage ;; esac
	local ref="${scope#secret:}" out
	out="$plain_dir/$ref.yaml"
	if [ -e "$out" ] || [ -e "$sealed_dir/$ref.yaml" ]; then
		echo "$ref already exists; unseal it and edit instead" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$out")"
	cat >"$out" <<EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: ${ref#*/}
  namespace: ${ref%%/*}
stringData:
  KEY: value
EOF
	echo "created $out; fill it in, then: scripts/secrets.sh seal $cluster --secret $ref"
}

case "$command" in
unseal) unseal ;;
seal) seal ;;
new) new ;;
*) usage ;;
esac
