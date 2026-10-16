#!/usr/bin/env bash
# P3-2: every object *we* own in podinfo-dev must carry the six standard
# labels + team (conventions.md). Skips the namespace's auto-created
# ServiceAccount/default and ConfigMap/kube-root-ca.crt.
# Usage: mise exec -- scripts/check-labels.sh
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

# kind/name pairs we own. Extend when P3-6 adds HTTPRoutes etc.
objects=(
	"Namespace/${NS}"
	"Deployment/podinfo"
	"Service/podinfo"
	"ServiceAccount/podinfo"
	"Secret/podinfo-config"
)

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
