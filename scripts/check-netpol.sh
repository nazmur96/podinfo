#!/usr/bin/env bash
# shellcheck disable=SC2015 # `cond && pass || fail` is safe: pass() only echoes
# P3-7: prove the NetworkPolicies in podinfo-dev do what they say, both ways.
# Run after scripts/deploy.sh. Exits 0 only if every check passes.
#   1. DNS works from a pod in podinfo-dev (allow-dns)
#   2. A pod in another namespace can't reach podinfo (no allow for it)
#   3. A pod in podinfo-dev can't reach podinfo either, even with its own
#      egress opened, so it's podinfo's ingress that stops it
#   4. The CUJ passes through the Gateway (allow-from-gateway)
#   5. A pod in the Envoy namespace that is NOT an Envoy proxy is blocked:
#      catches an allow whose namespace and pod selectors were split into
#      two `from` entries (any pod there would then be let in)
# Usage: mise exec -- scripts/check-netpol.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"

NS=podinfo-dev
PROBE_NS=netpol-probe
# Pinned: the probe must pass PSA restricted, so it can't be a root shell.
IMAGE=busybox:1.37.0@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
GW_NS=envoy-gateway-system
TARGET=podinfo.$NS.svc.cluster.local

failed=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

probe_pod() { # <namespace> <name>
	kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $2
  namespace: $1
  labels: { netpol-probe: "true" }
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  terminationGracePeriodSeconds: 0 # busybox sleep ignores SIGTERM
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: probe
      image: $IMAGE
      command: ["sleep", "600"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
EOF
	kubectl -n "$1" wait --for=condition=Ready "pod/$2" --timeout=60s >/dev/null
}

# 0 = got an HTTP answer; anything else = no connection within 5 s.
reach() { # <namespace> <pod>
	kubectl -n "$1" exec "$2" -- wget -q -T 5 -O /dev/null "http://$TARGET/version" 2>/dev/null
}

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
	kubectl delete ns "$PROBE_NS" --ignore-not-found --wait=false >/dev/null
	kubectl -n "$NS" delete pod netpol-probe --ignore-not-found --wait=false >/dev/null
	kubectl -n "$NS" delete networkpolicy probe-egress --ignore-not-found >/dev/null
	kubectl -n "$GW_NS" delete pod netpol-probe --ignore-not-found --wait=false >/dev/null
}
trap cleanup EXIT

# A previous run's cleanup doesn't wait; reusing objects that are still
# being deleted fails in odd ways.
kubectl delete ns "$PROBE_NS" --ignore-not-found --wait=true >/dev/null
kubectl -n "$NS" delete pod netpol-probe --ignore-not-found --wait=true >/dev/null
kubectl -n "$GW_NS" delete pod netpol-probe --ignore-not-found --wait=true >/dev/null
kubectl create ns "$PROBE_NS" >/dev/null
kubectl label ns "$PROBE_NS" --overwrite pod-security.kubernetes.io/enforce=restricted >/dev/null
probe_pod "$PROBE_NS" outside
probe_pod "$NS" netpol-probe
probe_pod "$GW_NS" netpol-probe

# 1. DNS from inside podinfo-dev.
kubectl -n "$NS" exec netpol-probe -- nslookup "$TARGET" >/dev/null 2>&1 &&
	pass "1 DNS from $NS resolves $TARGET" || fail "1 DNS from $NS (allow-dns)"

# 2. Another namespace: no policies there, so its egress is open; only
# podinfo's ingress can stop it.
reach "$PROBE_NS" outside && fail "2 pod in $PROBE_NS reached podinfo" ||
	pass "2 pod in $PROBE_NS can't reach podinfo (times out)"

# 3. Same namespace. default-deny also blocks the probe's own egress, which
# would make this pass for the wrong reason. Open the probe's egress first,
# and check that worked by reaching something podinfo-dev doesn't guard.
kubectl apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: probe-egress, namespace: $NS }
spec:
  podSelector: { matchLabels: { netpol-probe: "true" } }
  policyTypes: [Egress]
  egress: [{}]
EOF
sleep 2
if kubectl -n "$NS" exec netpol-probe -- nc -z -w 5 \
	kubernetes.default.svc.cluster.local 443 2>/dev/null; then
	reach "$NS" netpol-probe && fail "3 pod in $NS reached podinfo" ||
		pass "3 pod in $NS (egress open) can't reach podinfo (times out)"
else
	fail "3 probe egress didn't open: the check would prove nothing"
fi

# 4. The real path: Gateway → podinfo.
gw=$(curl -s -o /dev/null -w '%{http_code}' -m 15 --cacert .certs/ca.crt \
	https://podinfo.localhost/readyz 2>/dev/null)
if [ ! -f .certs/ca.crt ]; then
	fail "4 .certs/ca.crt missing: run scripts/install-local-platform.sh"
elif [ "$gw" != 200 ]; then
	# Envoy answers 503 after its 10 s connect timeout; don't wait 30 × that.
	fail "4 Gateway /readyz = $gw, want 200 (allow-from-gateway)"
else
	CURL_CA_BUNDLE=$ROOT/.certs/ca.crt BASE=https://podinfo.localhost \
		scripts/cuj.sh >/dev/null && pass "4 CUJ through the Gateway" ||
		fail "4 CUJ through the Gateway (allow-from-gateway)"
fi

# 5. Same namespace as Envoy, but not Envoy. No policies there, so its
# egress is open.
reach "$GW_NS" netpol-probe && fail "5 non-Envoy pod in $GW_NS reached podinfo (allow too broad)" ||
	pass "5 non-Envoy pod in $GW_NS can't reach podinfo (times out)"

[ "$failed" = 0 ] && echo "NetworkPolicy checks passed" || echo "NetworkPolicy checks FAILED"
exit "$failed"
