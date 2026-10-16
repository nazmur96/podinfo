#!/usr/bin/env bash
# P3-1: create the kind cluster and the podinfo-dev namespace.
# Tools from mise.toml (kind, kubectl). Runs against the host's Docker (ADR-0011).
# Usage: mise exec -- scripts/cluster-up.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"
mkdir -p "$(dirname "$KUBECONFIG")"

HOME_KUBE=${HOME}/.kube/config
home_mtime_before=
if [ -f "$HOME_KUBE" ]; then
	home_mtime_before=$(stat -c %Y "$HOME_KUBE" 2>/dev/null || stat -f %m "$HOME_KUBE")
fi

if kind get clusters 2>/dev/null | grep -qx podinfo; then
	echo "cluster 'podinfo' already exists; delete it first with scripts/cluster-down.sh" >&2
	exit 1
fi

echo "creating kind cluster podinfo (kubeconfig=$KUBECONFIG)"
kind create cluster --config kind/cluster.yaml --kubeconfig "$KUBECONFIG"

# Wait until all six nodes are Ready.
echo "waiting for nodes"
kubectl wait --for=condition=Ready node --all --timeout=180s

echo "applying kind/namespace.yaml"
kubectl apply -f kind/namespace.yaml

context=$(kubectl config current-context)
if [ "$context" != kind-podinfo ]; then
	echo "expected context kind-podinfo, got $context" >&2
	exit 1
fi

if [ -n "$home_mtime_before" ] && [ -f "$HOME_KUBE" ]; then
	home_mtime_after=$(stat -c %Y "$HOME_KUBE" 2>/dev/null || stat -f %m "$HOME_KUBE")
	if [ "$home_mtime_after" != "$home_mtime_before" ]; then
		echo "ERROR: $HOME_KUBE was modified; kind must write only to $KUBECONFIG" >&2
		exit 1
	fi
fi

echo "nodes:"
kubectl get nodes -o wide
echo "namespace:"
kubectl get ns podinfo-dev --show-labels
echo "OK: cluster up (context=$context, KUBECONFIG=$KUBECONFIG)"
