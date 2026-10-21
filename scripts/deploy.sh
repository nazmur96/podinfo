#!/usr/bin/env bash
# P3-2/P3-3: build the image, load it into kind, create the JWT Secret from
# .secrets/, apply k8s/overlays/dev. Namespace lives in k8s/base (not kind/).
# Usage: [OVERLAY=dev|dev-observed] mise exec -- scripts/deploy.sh
#   dev-observed (P3-10) adds metrics, OTLP, SLO rules; needs install-observability.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"

SHA=$(git rev-parse HEAD)
IMAGE=podinfo:${SHA}
SECRET_FILE=$ROOT/.secrets/config.yaml
OVERLAY=${OVERLAY:-dev}
[ -d "k8s/overlays/$OVERLAY" ] || { echo "no overlay k8s/overlays/$OVERLAY" >&2; exit 1; }

if [ ! -f "$SECRET_FILE" ]; then
	echo "missing $SECRET_FILE — run scripts/make-local-secret.sh first" >&2
	exit 1
fi

if ! kind get clusters 2>/dev/null | grep -qx podinfo; then
	echo "kind cluster 'podinfo' not found — run scripts/cluster-up.sh first" >&2
	exit 1
fi

# The overlay includes podinfo's HTTPRoute, which needs the Gateway API CRDs.
if ! kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
	echo "Gateway API not installed — run scripts/install-local-platform.sh first" >&2
	exit 1
fi

echo "building $IMAGE (REVISION=$SHA)"
docker build -t "$IMAGE" --build-arg "REVISION=$SHA" .

echo "loading $IMAGE into kind"
kind load docker-image "$IMAGE" --name podinfo

# Secret before the Deployment: pods mount it. Directory mount at /config
# (key config.yaml → /config/config.yaml). No subPath (D5).
echo "applying Secret podinfo-config in podinfo-dev"
# Namespace may not exist yet on a fresh cluster — create it from base first.
kubectl apply -f k8s/base/namespace.yaml
# Labels match conventions.md so check-labels.sh passes for the Secret too.
kubectl -n podinfo-dev create secret generic podinfo-config \
	--from-file=config.yaml="$SECRET_FILE" \
	--dry-run=client -o yaml |
	kubectl apply -f -
kubectl -n podinfo-dev label secret podinfo-config --overwrite \
	app.kubernetes.io/name=podinfo \
	app.kubernetes.io/instance=podinfo-dev \
	app.kubernetes.io/component=api \
	app.kubernetes.io/part-of=podinfo \
	app.kubernetes.io/managed-by=kubectl \
	team=nazmur96

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -a k8s "$tmp/k8s"
# Rewrite the image tag in the temp overlay only — never dirty the worktree.
sed -i "s|^[[:space:]]*newTag:.*|    newTag: ${SHA}|" "$tmp/k8s/overlays/dev/kustomization.yaml"

echo "applying kustomize overlay $OVERLAY (image=$IMAGE)"
# Capture apply output so PSA warnings are visible in CI logs / reviews.
apply_out=$(kubectl apply -k "$tmp/k8s/overlays/$OVERLAY" 2>&1)
printf '%s\n' "$apply_out"
if printf '%s\n' "$apply_out" | grep -qi 'warning.*violates\|warning.*podsecurity\|would violate PodSecurity'; then
	echo "ERROR: kubectl apply produced a PSA warning" >&2
	exit 1
fi

echo "waiting for rollout"
kubectl -n podinfo-dev rollout status deploy/podinfo --timeout=120s
kubectl -n podinfo-dev get pods -o wide
echo "OK: deployed $IMAGE"
