#!/usr/bin/env bash
# Run from the repo root: bash gitops/sources/ca-certmate-cloudflare-mesh/tests/test_p5_gunicorn_timeout.sh
#
# Property 5: Gunicorn timeout is sufficient for DNS propagation
# Parse stack.env and extract the value of GUNICORN_TIMEOUT.
# Assert the value is a parseable non-negative integer and is >= 300.
# (DNS-01 challenge propagation can take up to 5 minutes; a lower timeout
# causes workers to time out before the DNS record is confirmed, resulting
# in failed certificate issuance.)
# Validates: Requirements 7.4

set -euo pipefail

STACK_ENV="gitops/sources/ca-certmate-cloudflare-mesh/stack.env"

if [[ ! -f "$STACK_ENV" ]]; then
  echo "ERROR: stack.env not found: $STACK_ENV" >&2
  exit 1
fi

MIN_TIMEOUT=300

# Extract the GUNICORN_TIMEOUT value (ignore comment lines)
timeout_line=$(grep -E "^[[:space:]]*GUNICORN_TIMEOUT=" "$STACK_ENV" | grep -v '^[[:space:]]*#' || true)

if [[ -z "$timeout_line" ]]; then
  echo "FAIL — GUNICORN_TIMEOUT is not set in $STACK_ENV" >&2
  exit 1
fi

timeout_value="${timeout_line#*=}"

# Strip surrounding whitespace
timeout_value="${timeout_value#"${timeout_value%%[![:space:]]*}"}"
timeout_value="${timeout_value%"${timeout_value##*[![:space:]]}"}"

if [[ -z "$timeout_value" ]]; then
  echo "FAIL — GUNICORN_TIMEOUT is assigned but has an empty value in $STACK_ENV" >&2
  exit 1
fi

# Assert the value is a non-negative integer
if ! [[ "$timeout_value" =~ ^[0-9]+$ ]]; then
  echo "FAIL — GUNICORN_TIMEOUT value '$timeout_value' is not a non-negative integer" >&2
  exit 1
fi

# Assert the value is >= 300
if (( timeout_value < MIN_TIMEOUT )); then
  echo "FAIL — GUNICORN_TIMEOUT=$timeout_value is below the required minimum of $MIN_TIMEOUT seconds" >&2
  echo "       DNS-01 challenge propagation can take up to 5 minutes; lower values cause certificate issuance failures." >&2
  exit 1
fi

echo "PASS — Property 5: GUNICORN_TIMEOUT=$timeout_value >= $MIN_TIMEOUT (DNS propagation requirement satisfied)"
