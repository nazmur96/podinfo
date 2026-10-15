#!/usr/bin/env bash
# P2-5 size budget: exit 1 if an image is bigger than its budget.
# Usage: scripts/check-image-size.sh <image> <budget-MiB>
#
# Measures what `docker image inspect` reports: the unpacked size on disk.
# The registry stores a smaller, compressed copy; the budget is for the
# unpacked size. Compares in bytes, so 30.9 MiB fails a 30 MiB budget.
set -euo pipefail

image=${1:?usage: $0 <image> <budget-MiB>}
budget_mib=${2:?usage: $0 <image> <budget-MiB>}

bytes=$(docker image inspect "$image" --format '{{.Size}}')
limit=$((budget_mib * 1024 * 1024))
mib=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b / 1048576 }')

echo "$image: ${mib} MiB (${bytes} bytes), budget ${budget_mib} MiB"
if [ "$bytes" -gt "$limit" ]; then
	echo "::error::$image is over its size budget (${mib} MiB > ${budget_mib} MiB)"
	exit 1
fi
