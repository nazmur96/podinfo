#!/usr/bin/env bash
# P3-6: Gateway API CRDs + Envoy Gateway + cert-manager + local Gateway/TLS.
# Pins are intentional (D8). Re-run is idempotent (helm upgrade --install).
# Usage: mise exec -- scripts/install-local-platform.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"

EG_CHART=oci://docker.io/envoyproxy/gateway-helm
EG_VERSION=v1.9.2
CM_CHART=oci://quay.io/jetstack/charts/cert-manager
CM_VERSION=v1.19.1

if ! kind get clusters 2>/dev/null | grep -qx podinfo; then
	echo "kind cluster 'podinfo' not found — run scripts/cluster-up.sh first" >&2
	exit 1
fi

echo "applying platform namespaces (PSA restricted, labelled; helm doesn't create them)"
kubectl apply -f k8s/local/namespace.yaml

echo "installing Envoy Gateway ${EG_VERSION} (includes Gateway API standard CRDs)"
helm upgrade --install eg "$EG_CHART" \
	--version "$EG_VERSION" \
	--namespace envoy-gateway-system \
	--wait \
	--timeout 5m

echo "waiting for Envoy Gateway controller"
kubectl -n envoy-gateway-system wait --for=condition=Available \
	deploy/envoy-gateway --timeout=180s

echo "installing cert-manager ${CM_VERSION} (Gateway API support on)"
helm upgrade --install cert-manager "$CM_CHART" \
	--version "$CM_VERSION" \
	--namespace cert-manager \
	--values k8s/local/cert-manager-values.yaml \
	--wait \
	--timeout 5m

echo "waiting for cert-manager"
kubectl -n cert-manager wait --for=condition=Available \
	deploy/cert-manager deploy/cert-manager-webhook deploy/cert-manager-cainjector \
	--timeout=180s

echo "applying ClusterIssuer + local CA"
kubectl apply -f k8s/local/clusterissuer.yaml
# CA Certificate must become Ready before ClusterIssuer local-ca can sign.
kubectl -n cert-manager wait --for=condition=Ready certificate/local-ca --timeout=120s

echo "exporting CA to .certs/ca.crt (D7: per-command CURL_CA_BUNDLE, not system trust)"
mkdir -p .certs
kubectl -n cert-manager get secret local-ca-secret \
	-o jsonpath='{.data.ca\.crt}' | base64 -d >.certs/ca.crt
# Also try tls.crt if ca.crt key is absent (self-signed CA secrets vary).
if [ ! -s .certs/ca.crt ]; then
	kubectl -n cert-manager get secret local-ca-secret \
		-o jsonpath='{.data.tls\.crt}' | base64 -d >.certs/ca.crt
fi
if [ ! -s .certs/ca.crt ]; then
	echo "failed to write .certs/ca.crt from local-ca-secret" >&2
	exit 1
fi
chmod 644 .certs/ca.crt

echo "applying EnvoyProxy (NodePorts 30080/30443), GatewayClass, Gateway"
kubectl apply -f k8s/local/envoyproxy-nodeport.yaml
kubectl apply -f k8s/local/gatewayclass.yaml
kubectl apply -f k8s/local/gateway.yaml

echo "applying the HTTP→HTTPS redirect route"
# podinfo's own route lives with the app (k8s/overlays/dev/httproute.yaml) and
# is applied by scripts/deploy.sh, after this script. Order: cluster-up →
# install-local-platform → deploy. The gateway-access label on podinfo-dev is
# owned by k8s/base/namespace.yaml.
kubectl apply -f k8s/local/httproute-redirect.yaml

echo "waiting for Gateway public to be programmed"
# Gateway status can take a moment after EnvoyProxy Service gets NodePorts.
for _ in $(seq 1 60); do
	if kubectl -n gateway get gateway public \
		-o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null | grep -qx True; then
		break
	fi
	sleep 2
done
kubectl -n gateway get gateway public
kubectl -n gateway get certificate 2>/dev/null || true

echo "checking Envoy Service NodePorts (expect 30080 and 30443)"
# EG places the data-plane Service in envoy-gateway-system (not the Gateway ns).
svc_ns=envoy-gateway-system
svc=$(kubectl -n "$svc_ns" get svc \
	-l gateway.envoyproxy.io/owning-gateway-name=public,gateway.envoyproxy.io/owning-gateway-namespace=gateway \
	-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$svc" ]; then
	# Fallback: any NodePort owned by this Gateway (any namespace)
	read -r svc_ns svc < <(kubectl get svc -A -o json |
		jq -r '.items[]
			| select(.spec.type=="NodePort")
			| select(.metadata.labels["gateway.envoyproxy.io/owning-gateway-name"]=="public")
			| "\(.metadata.namespace) \(.metadata.name)"' | head -1)
fi
if [ -n "${svc:-}" ]; then
	kubectl -n "$svc_ns" get svc "$svc" -o wide
	ports=$(kubectl -n "$svc_ns" get svc "$svc" -o jsonpath='{.spec.ports[*].nodePort}')
	echo "NodePorts: $ports"
	echo "$ports" | grep -qw 30080 || {
		echo "ERROR: expected NodePort 30080" >&2
		exit 1
	}
	echo "$ports" | grep -qw 30443 || {
		echo "ERROR: expected NodePort 30443" >&2
		exit 1
	}
else
	echo "ERROR: Envoy Service not found for Gateway public" >&2
	exit 1
fi

cat <<EOF
OK: local platform installed
  CA:   $ROOT/.certs/ca.crt
  CUJ:  CURL_CA_BUNDLE=$ROOT/.certs/ca.crt BASE=https://podinfo.localhost EXPECT_SHA=\$(git rev-parse HEAD) scripts/cuj.sh
  Next: scripts/deploy.sh (applies podinfo and its HTTPRoute)
EOF
