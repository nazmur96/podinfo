#!/usr/bin/env bash
# P3-1: delete the kind cluster. Leaves .kube/config in place so a failed
# up/down cycle is still inspectable; delete it yourself if you want a blank slate.
# Usage: mise exec -- scripts/cluster-down.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"

if ! kind get clusters 2>/dev/null | grep -qx podinfo; then
	echo "cluster 'podinfo' not found; nothing to delete"
	exit 0
fi

echo "deleting kind cluster podinfo"
kind delete cluster --name podinfo --kubeconfig "$KUBECONFIG"
echo "OK: cluster down"
