#!/usr/bin/env bash
# Run from the repo root: bash gitops/sources/ca-certmate-cloudflare-mesh/tests/test_p4_empty_secrets.sh
#
# Property 4: Committed stack.env contains no secret values
# For each secret variable, assert the assigned value is the empty string
# (i.e., the line is exactly VAR= with nothing after the equals sign).
# Validates: Requirements 8.1

set -euo pipefail

STACK_ENV="gitops/sources/ca-certmate-cloudflare-mesh/stack.env"

if [[ ! -f "$STACK_ENV" ]]; then
  echo "ERROR: stack.env not found: $STACK_ENV" >&2
  exit 1
fi

SECRET_VARS=(
  "TUNNEL_TOKEN"
  "CLOUDFLARE_TOKEN"
  "API_BEARER_TOKEN"
  "SECRET_KEY"
  "CERTMATE_BACKUP_PASSPHRASE"
)

fail=0

for var in "${SECRET_VARS[@]}"; do
  # Look for a non-comment line that assigns this variable.
  # Match: optional leading whitespace, VAR=<anything>, not starting with #
  line=$(grep -E "^[[:space:]]*${var}=" "$STACK_ENV" | grep -v '^[[:space:]]*#' || true)

  if [[ -z "$line" ]]; then
    echo "FAIL — '$var' has no assignment line in $STACK_ENV" >&2
    fail=1
    continue
  fi

  # Extract the value (everything after the first '=')
  # Strip \r to handle CRLF (Windows) line endings gracefully
  value="${line#*=}"
  value="${value//$'\r'/}"

  if [[ -n "$value" ]]; then
    echo "FAIL — '$var' has a non-empty value committed in $STACK_ENV (found: '${value}')" >&2
    echo "       Secret values must never be committed to source control." >&2
    fail=1
  else
    echo "PASS — '$var' is empty (no secret value committed)"
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "" >&2
  echo "FAIL — Property 4 (Committed stack.env contains no secret values): one or more secrets have non-empty values" >&2
  exit 1
fi

echo "PASS — Property 4: all secret variables have empty values in committed stack.env"
