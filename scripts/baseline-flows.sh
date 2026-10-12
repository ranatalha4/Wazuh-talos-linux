#!/usr/bin/env bash
# Build a unique flow baseline (src -> dst, direction, action) from Wazuh archives.json.
# Run on the Wazuh Manager. Needs logall_json enabled temporarily. awk/grep only, no Python or jq.
#
# Usage: sudo ./baseline-flows.sh [lines] [archives.json]
# Set the field names to whatever your decoder extracts:
#   SRC=src_pod DST=dst_pod DIR=direction ACT=action sudo -E ./baseline-flows.sh
set -u
LINES="${1:-300000}"
FILE="${2:-/var/ossec/logs/archives/archives.json}"
SRC="${SRC:-src_pod}"; DST="${DST:-dst_pod}"; DIR="${DIR:-direction}"; ACT="${ACT:-action}"

tail -n "$LINES" "$FILE" | grep "\"$SRC\"" | awk -v s="$SRC" -v d="$DST" -v r="$DIR" -v a="$ACT" '
function get(k,   m) { if (match($0, "\"" k "\":\"[^\"]*\"")) { m = substr($0, RSTART, RLENGTH); sub(/^"[^"]*":"/, "", m); sub(/"$/, "", m); return m } return "-" }
{ c[get(r) " | " get(a) " | " get(s) " -> " get(d)]++ }
END { for (k in c) printf "%8d  %s\n", c[k], k }' | sort -rn
