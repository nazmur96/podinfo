#!/usr/bin/env bash
# P3-9: run podinfo on this machine as if it were a podinfo pod: its env, its
# mounted /config Secret, its DNS, and (steal mode) that pod's share of the
# Gateway's traffic. Checks: /version via the Gateway shows commit "unknown"
# (a local build) for part of the requests.
# The agent is privileged, so it gets its own namespace, labelled privileged:
# the one PSA exception (ADR-0012), local only.
# Usage: mise exec -- scripts/mirrord.sh [command…]
#   default: build ./cmd/podinfo, run it with the image's CMD flags
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"

kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: mirrord
  labels:
    app.kubernetes.io/name: mirrord
    app.kubernetes.io/instance: podinfo-local
    app.kubernetes.io/component: dev-tool
    app.kubernetes.io/part-of: podinfo
    app.kubernetes.io/managed-by: kubectl
    team: nazmur96
    # ADR-0012: mirrord's agent joins the target pod's namespaces (hostPID).
    pod-security.kubernetes.io/enforce: privileged
YAML

if [ $# = 0 ]; then
	# mirrord loads through LD_PRELOAD, which a static binary ignores, and
	# `go run` builds one here (no C compiler, so cgo is off). It also skips
	# build tools like `go` on purpose. So: build a dynamically linked binary
	# with zig as the C compiler (from mise; the host stays clean), run that.
	CGO_ENABLED=1 CC="zig cc" go build -o bin/podinfo-mirrord ./cmd/podinfo
	set -- bin/podinfo-mirrord --port=9898 --ui-path=./ui --data-path=/tmp/podinfo-data
fi
exec mirrord exec -f .mirrord/mirrord.yaml -- "$@"
