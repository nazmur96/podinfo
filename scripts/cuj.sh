#!/usr/bin/env bash
# shellcheck disable=SC2015 # `cond && pass || fail` is safe: pass() only echoes
# P2-8: the critical user journey (platform docs/cuj.md) as a script.
# Exits 0 only if every step passes. Used from here on as the definition of
# "it works": Compose (P2), kind (P3), EKS (P4+), CI (P7), load tests (P10).
#
# Usage: [BASE=http://localhost:9898] [EXPECT_SHA=<full sha>] [STEP7=skip] scripts/cuj.sh
#   EXPECT_SHA  step 1 must return exactly this commit (CI images); unset: anything but "unknown"
#   STEP7=skip  only where the real JWT secret isn't wired (e.g. a bare `make run`)
# Needs: curl, jq.
set -uo pipefail

BASE=${BASE:-http://localhost:9898}
EXPECT_SHA=${EXPECT_SHA:-}
STEP7=${STEP7:-run}

# Signed with upstream's published default secret (cmd/podinfo/main.go,
# SetDefault "jwt-secret"); claims name=cuj-forged, iss=podinfo, exp=2100.
# Public on purpose: it must FAIL against a real deployment (step 7).
DEFAULT_SIGNED_TOKEN='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQxMDI0NDQ4MDAsImlzcyI6InBvZGluZm8iLCJuYW1lIjoiY3VqLWZvcmdlZCJ9.CjLpFiGWGijyPx338OqFKdUr-gJUbIUW0kjVwRqWd_s' # gitleaks:allow

failed=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

ready=0
for _ in $(seq 1 30); do
	[ "$(code "$BASE/readyz")" = 200 ] && ready=1 && break
	sleep 1
done
if [ "$ready" = 0 ]; then
	echo "FAIL $BASE/readyz not 200 after 30 s: is the app running?"
	echo "CUJ FAILED"
	exit 1
fi

# 1. The running build knows its commit.
commit=$(curl -s "$BASE/version" | jq -r .commit)
if [ -n "$EXPECT_SHA" ]; then
	[ "$commit" = "$EXPECT_SHA" ] && pass "1 /version commit = $commit" || fail "1 /version commit=$commit, want $EXPECT_SHA"
else
	[ -n "$commit" ] && [ "$commit" != unknown ] && [ "$commit" != null ] && pass "1 /version commit = $commit" || fail "1 /version commit=$commit"
fi

# 2-3. Liveness and readiness.
[ "$(curl -s "$BASE/healthz" | jq -r .status)" = OK ] && pass "2 /healthz" || fail "2 /healthz"
[ "$(curl -s "$BASE/readyz" | jq -r .status)" = OK ] && pass "3 /readyz" || fail "3 /readyz"

# 4. The app path is served (curl gets JSON, browsers get the UI).
curl -s -A curl "$BASE/" | jq -e '.hostname and .version and .revision' >/dev/null && pass "4 / JSON" || fail "4 / JSON"

# 5-6. Token issued, then validated with the same secret. Run back to back:
# tokens expire after 1 minute.
token=$(curl -s -X POST -d cuj "$BASE/token" | jq -r .token)
[ -n "$token" ] && [ "$token" != null ] && pass "5 POST /token" || fail "5 POST /token"
name=$(curl -s -H "Authorization: Bearer $token" "$BASE/token/validate" | jq -r .token_name)
[ "$name" = cuj ] && pass "6 /token/validate token_name=cuj" || fail "6 /token/validate token_name=$name"

# 7. A token signed with upstream's default secret is refused: we are not
# running the hardcoded default.
if [ "$STEP7" = skip ]; then
	echo "SKIP 7 (STEP7=skip: real secret not wired here)"
else
	c=$(code -H "Authorization: Bearer $DEFAULT_SIGNED_TOKEN" "$BASE/token/validate")
	[ "$c" = 401 ] && pass "7 default-signed token → 401" || fail "7 default-signed token → $c (want 401: running on the default secret?)"
fi

# 8. Gated routes are gone. Dangerous ones are probed with a wrong method so
# they never run: 404 = not registered, 405 = still there (gate regressed).
for probe in "GET /env" "GET /configs" "GET /debug/pprof/" "POST /panic" "POST /delay/1" \
	"GET /store" "GET /fault_injection/enable" "GET /readyz/disable" "GET /chunked"; do
	m=${probe%% *} p=${probe#* }
	c=$(code -X "$m" "$BASE$p")
	[ "$c" = 404 ] && pass "8 $m $p → 404" || fail "8 $m $p → $c (want 404)"
done

[ "$failed" = 0 ] && echo "CUJ passed" || echo "CUJ FAILED"
exit "$failed"
