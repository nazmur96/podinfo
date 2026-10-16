#!/usr/bin/env bash
# P2-7: create the git-ignored JWT secret that compose.yaml mounts as a file
# (ADR-0006: the secret arrives as config.yaml, never as an env var, because
# env vars leak more easily: `docker inspect`, crash dumps, the /env route).
# Safe to re-run: an existing secret is kept.
set -euo pipefail

cd "$(dirname "$0")/.."
file=.secrets/config.yaml

if [ -f "$file" ]; then
	echo "$file exists, keeping it"
	exit 0
fi

mkdir -p .secrets
secret=$(head -c 48 /dev/urandom | base64 | tr -d '\n/+=')
printf 'jwt-secret: "%s"\n' "$secret" >"$file"
# Readable by the container's user (65532), which isn't you. This is a
# throwaway local secret; real ones come from Secrets Manager (P5).
chmod 0644 "$file"
echo "created $file"
