#!/usr/bin/env bash
# P3-8: zero failed requests while pods are replaced. Sends requests through
# the Gateway in a tight loop while <action> runs, then tallies the status
# codes. Exits 0 only if every request got a 200.
# Usage: mise exec -- scripts/rollout-drill.sh restart
#        mise exec -- scripts/rollout-drill.sh drain <node>
# Never run this with podinfo at --level=debug: debug skips its 3 s drain
# sleep (platform questions.md #4), so it would test a different shutdown.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
export KUBECONFIG="${KUBECONFIG:-$ROOT/.kube/config}"
URL=${URL:-https://podinfo.localhost/version}
NS=podinfo-dev
out=$(mktemp)
trap 'rm -f "$out"' EXIT

loop() {
	while [ ! -f "$out.stop" ]; do
		curl -s -o /dev/null -w '%{http_code}\n' -m 5 --cacert .certs/ca.crt "$URL" >>"$out"
	done
}

loop &
pid=$!
action_failed=0
sleep 3 # a baseline before anything moves

case ${1:-} in
restart)
	kubectl -n "$NS" rollout restart deploy/podinfo >/dev/null &&
		kubectl -n "$NS" rollout status deploy/podinfo --timeout=180s >/dev/null || action_failed=1
	;;
drain)
	node=${2:?usage: rollout-drill.sh drain <node>}
	# A drain that fails moves nothing, and the tally would be a false pass.
	kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=180s >/dev/null &&
		kubectl -n "$NS" rollout status deploy/podinfo --timeout=180s >/dev/null || action_failed=1
	;;
*)
	echo "usage: rollout-drill.sh restart | drain <node>" >&2
	touch "$out.stop"
	wait "$pid"
	rm -f "$out.stop"
	exit 2
	;;
esac

sleep 10 # old pods finish terminating while the loop keeps going
touch "$out.stop"
wait "$pid"
rm -f "$out.stop"
[ "${1}" = drain ] && kubectl uncordon "$2" >/dev/null

sort "$out" | uniq -c
total=$(wc -l <"$out")
bad=$(grep -vc '^200$' "$out")
echo "requests=$total non-200=$bad"
if [ "$action_failed" = 1 ]; then
	echo "FAIL the $1 itself failed: the tally proves nothing"
	exit 1
fi
[ "$bad" = 0 ]
