#!/usr/bin/env bash
# P3-2: every object *we* own in podinfo-dev must carry the six standard
# labels + team (conventions.md). "We own" = whatever k8s/overlays/dev
# renders, plus the Secret scripts/deploy.sh creates, so a new manifest is
# checked without editing this script. Auto-created objects (the default
# ServiceAccount, kube-root-ca.crt) aren't rendered, so they're never checked.
# Usage: [OVERLAY=dev|dev-observed] mise exec -- scripts/check-labels.sh
set -euo pipefail

cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$PWD/.kube/config}"

NS=podinfo-dev
required=(
	app.kubernetes.io/name
	app.kubernetes.io/instance
	app.kubernetes.io/component
	app.kubernetes.io/part-of
	app.kubernetes.io/managed-by
	team
)

mapfile -t objects < <(
	kubectl apply -k "k8s/overlays/${OVERLAY:-dev}" --dry-run=client -o json |
		jq -r '(.items // [.])[] | "\(.kind)/\(.metadata.name)"'
)
objects+=("Secret/podinfo-config") # created by scripts/deploy.sh, not kustomize
if [ "${#objects[@]}" -lt 2 ]; then
	echo "FAIL could not render k8s/overlays/${OVERLAY:-dev}" >&2
	exit 1
fi

failed=0
for obj in "${objects[@]}"; do
	kind=${obj%%/*}
	name=${obj#*/}
	if [ "$kind" = Namespace ]; then
		json=$(kubectl get ns "$name" -o json)
	else
		json=$(kubectl -n "$NS" get "$kind" "$name" -o json)
	fi
	missing=
	for key in "${required[@]}"; do
		val=$(printf '%s' "$json" | jq -r --arg k "$key" '.metadata.labels[$k] // empty')
		if [ -z "$val" ]; then
			missing="${missing} ${key}"
		fi
	done
	if [ -n "$missing" ]; then
		echo "FAIL $obj missing:$missing"
		failed=1
	else
		echo "PASS $obj"
	fi
done

if [ "$failed" != 0 ]; then
	echo "label check FAILED"
	exit 1
fi
echo "label check passed"
