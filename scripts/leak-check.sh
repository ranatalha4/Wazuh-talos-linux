#!/usr/bin/env bash
# Scan the repo for things that must not be published. Run from the repo root before every push.
# Add your own internal domains/hostnames to EXTRA (pipe-separated), e.g. EXTRA='corp\.local|siem01'
set -u
EXTRA="${EXTRA:-}"
PATTERN='(^|[^0-9])(10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+)|password|passwd|secret|token|api[_-]?key|BEGIN [A-Z ]*PRIVATE KEY'
[ -n "$EXTRA" ] && PATTERN="$PATTERN|$EXTRA"
if grep -rniE --exclude-dir=.git --exclude=leak-check.sh "$PATTERN" . ; then
  echo "LEAK CHECK FAILED: review the lines above before pushing." >&2; exit 1
fi
echo "Leak check passed."
