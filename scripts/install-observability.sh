#!/usr/bin/env bash
# P3-10: the demo-grade observability stack (Prometheus, Alertmanager,
# Grafana, Loki, Tempo, Alloy) in namespace observability. Optional and heavy
# (~2-3 GiB): run after install-local-platform.sh, then deploy podinfo with
# OVERLAY=dev-observed so it is scraped, traced and alerted on.
# Pins are intentional (D8). Re-run is idempotent.
# Usage: mise exec -- scripts/install-observability.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"
DIR=k8s/local/observability

KPS_VERSION=92.11.0  # prometheus-community/kube-prometheus-stack
LOKI_VERSION=7.3.0   # grafana/loki (Loki 3.6)
TEMPO_VERSION=3.2.0  # grafana-community/tempo (Tempo 3.1); grafana/tempo is deprecated
ALLOY_VERSION=1.14.0 # grafana/alloy (Alloy 1.21)
PROM_REPO=https://prometheus-community.github.io/helm-charts
GRAFANA_REPO=https://grafana.github.io/helm-charts
COMMUNITY_REPO=https://grafana-community.github.io/helm-charts

kubectl apply -f "$DIR/namespace.yaml"

# Grafana admin password: random, created once, never in git.
if ! kubectl -n observability get secret grafana-admin >/dev/null 2>&1; then
	kubectl -n observability create secret generic grafana-admin \
		--from-literal=admin-user=admin \
		--from-literal=admin-password="$(head -c 24 /dev/urandom | base64 | tr -d '\n/+=')"
fi

install() { # <release> <chart> <repo> <version>
	echo "installing $1 ($2 $4)"
	helm upgrade --install "$1" "$2" --repo "$3" --version "$4" \
		--namespace observability --values "$DIR/$1-values.yaml" \
		--wait --timeout 10m
}
install kube-prometheus-stack kube-prometheus-stack "$PROM_REPO" "$KPS_VERSION"
install loki loki "$GRAFANA_REPO" "$LOKI_VERSION"
install tempo tempo "$COMMUNITY_REPO" "$TEMPO_VERSION"
install alloy alloy "$GRAFANA_REPO" "$ALLOY_VERSION"

kubectl apply -f "$DIR/alert-sink.yaml"
kubectl -n observability rollout status deploy/alert-sink --timeout=120s

kubectl -n observability get pods
cat <<'MSG'
OK: observability stack installed (demo-grade: 1 replica each, 24 h retention)
  Next:     OVERLAY=dev-observed scripts/deploy.sh
  Grafana:  kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
            user admin, password:
            kubectl -n observability get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
MSG
