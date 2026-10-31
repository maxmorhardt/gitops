#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage:
  scripts/secrets.sh get    <cluster> <namespace>/<name> [KEY]
  scripts/secrets.sh set    <cluster> <namespace>/<name> KEY=value...
  scripts/secrets.sh new    <cluster> <namespace>/<name> KEY=value... [--type <type>] [--label key=value]
  scripts/secrets.sh unseal <cluster> --all | --namespace <namespace> | --secret <namespace>/<name>
  scripts/secrets.sh seal   <cluster> --all | --namespace <namespace> | --secret <namespace>/<name>
  scripts/secrets.sh backup-key <cluster>
  scripts/secrets.sh clean

  get         print a secret's values, or one value
  set         change or add values in a sealed secret and re-seal it
  new         create and seal a secret that doesn't exist yet
  unseal      write secrets as plain YAML to .secrets/<cluster>/<namespace>/<name>.yaml to edit
  seal        encrypt edited files in .secrets/<cluster>/ back into clusters/<cluster>/secrets/
  backup-key  save the cluster's sealing key to scripts/keys/<cluster>.yaml (gitignored)
  clean       delete .secrets/

A bare KEY= prompts for the value without echoing it, keeping it out of shell history;
KEY=@path reads the value from a file.
Decryption uses scripts/keys/<cluster>.yaml when present, otherwise the live cluster.
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

sealed_dir="clusters/$cluster/secrets"
plain_dir="$plain_root/$cluster"
cert="clusters/$cluster/pub-cert.pem"
key="scripts/keys/$cluster.yaml"

ensure_cert() {
	if [ ! -f "$cert" ]; then
		kubeseal --context "$cluster" --controller-name sealed-secrets --controller-namespace sealed-secrets \
			--fetch-cert >"$cert"
	fi
}

# <namespace>/<name> of a secret that exists in git
existing() {
	local ref="$1"
	case "$ref" in */*) ;; *) usage ;; esac
	if [ ! -f "$sealed_dir/$ref.yaml" ]; then
		echo "no sealed secret $sealed_dir/$ref.yaml" >&2
		exit 1
	fi
}

# the decrypted Secret as JSON
decrypt() {
	local ref="$1"
	if [ -f "$key" ]; then
		kubeseal --recovery-unseal --recovery-private-key "$key" -o json <"$sealed_dir/$ref.yaml"
	else
		kubectl --context "$cluster" get secret "${ref#*/}" -n "${ref%%/*}" -o json
	fi
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

# apply KEY=value arguments to the Secret YAML on stdin; a bare KEY= prompts
with_values() {
	local yaml
	yaml=$(cat)
	for pair in "$@"; do
		case "$pair" in *=*) ;; *) echo "expected KEY=value, got '$pair'" >&2; exit 1 ;; esac
		local k="${pair%%=*}" v="${pair#*=}"
		if [ -z "$v" ]; then
			read -r -s -p "$k: " v </dev/tty
			echo >&2
		elif [ "${v:0:1}" = @ ] && [ -f "${v:1}" ]; then
			v=$(cat "${v:1}")
		fi
		yaml=$(echo "$yaml" | K="$k" V="$v" yq '.stringData[strenv(K)] = strenv(V)')
	done
	echo "$yaml"
}

# sealed in memory first: set reads the same file it rewrites, and a failed seal must not truncate it
seal_to() {
	local ref="$1" sealed
	ensure_cert
	mkdir -p "$sealed_dir/${ref%%/*}"
	sealed=$(kubeseal --format yaml --cert "$cert")
	echo "$sealed" >"$sealed_dir/$ref.yaml"
	echo "sealed $sealed_dir/$ref.yaml"
}

# --all | --namespace | --secret -> matching <namespace>/<name> under a directory
matching() {
	local root="$1" which="$2"
	[ -d "$root" ] || return 0
	(cd "$root" && find . -mindepth 2 -maxdepth 2 -name '*.yaml' | sed 's#^\./##; s#\.yaml$##' | sort) |
		while read -r ref; do
			case "$which" in
			all) echo "$ref" ;;
			ns:*) [ "${ref%%/*}" = "${which#ns:}" ] && echo "$ref" || true ;;
			secret:*) [ "$ref" = "${which#secret:}" ] && echo "$ref" || true ;;
			esac
		done
}

which_secrets() {
	case "${1:-}" in
	--all) echo all ;;
	--namespace) echo "ns:${2:?--namespace needs a value}" ;;
	--secret) echo "secret:${2:?--secret needs <namespace>/<name>}" ;;
	*) usage ;;
	esac
}

case "$command" in
get)
	ref="${1:-}"
	existing "$ref"
	if [ -n "${2:-}" ]; then
		decrypt "$ref" | K="$2" jq -r '.data[env.K] // error("no key \(env.K)") | @base64d'
	else
		decrypt "$ref" | jq -r '.data // {} | to_entries[] | "\(.key)=\(.value | @base64d)"'
	fi
	;;

set)
	ref="${1:-}"
	existing "$ref"
	shift
	[ $# -gt 0 ] || usage
	decrypt "$ref" | readable | with_values "$@" | seal_to "$ref"
	;;

new)
	ref="${1:-}"
	case "$ref" in */*) ;; *) usage ;; esac
	shift
	if [ -f "$sealed_dir/$ref.yaml" ]; then
		echo "$ref already exists; use set" >&2
		exit 1
	fi
	type=Opaque
	labels=()
	pairs=()
	while [ $# -gt 0 ]; do
		case "$1" in
		--type) type="${2:?--type needs a value}"; shift ;;
		--label) labels+=("${2:?--label needs key=value}"); shift ;;
		*) pairs+=("$1") ;;
		esac
		shift
	done
	[ ${#pairs[@]} -gt 0 ] || usage
	yaml=$(N="${ref#*/}" NS="${ref%%/*}" T="$type" yq -n '
		.apiVersion = "v1" | .kind = "Secret" | .type = strenv(T)
		| .metadata.name = strenv(N) | .metadata.namespace = strenv(NS)')
	for label in "${labels[@]}"; do
		yaml=$(echo "$yaml" | K="${label%%=*}" V="${label#*=}" yq '.metadata.labels[strenv(K)] = strenv(V)')
	done
	echo "$yaml" | with_values "${pairs[@]}" | seal_to "$ref"
	;;

unseal)
	which=$(which_secrets "$@")
	refs=$(matching "$sealed_dir" "$which")
	[ -n "$refs" ] || { echo "no sealed secrets match" >&2; exit 1; }
	for ref in $refs; do
		out="$plain_dir/$ref.yaml"
		mkdir -p "$(dirname "$out")"
		decrypt "$ref" | readable >"$out"
		echo "unsealed $ref -> $out"
	done
	;;

seal)
	which=$(which_secrets "$@")
	refs=$(matching "$plain_dir" "$which")
	[ -n "$refs" ] || { echo "nothing in $plain_dir matches; unseal first" >&2; exit 1; }
	for ref in $refs; do
		in="$plain_dir/$ref.yaml"
		if [ "$(yq '.metadata.namespace' "$in")" != "${ref%%/*}" ] || [ "$(yq '.metadata.name' "$in")" != "${ref#*/}" ]; then
			echo "$in: metadata.namespace/name must be $ref" >&2
			exit 1
		fi
		seal_to "$ref" <"$in"
	done
	;;

backup-key)
	mkdir -p "$(dirname "$key")"
	kubectl --context "$cluster" get secret -n sealed-secrets \
		-l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >"$key"
	echo "saved $key; keep a copy outside this repo too"
	;;

*) usage ;;
esac
