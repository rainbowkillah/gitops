#!/usr/bin/env bash
# Run from the repo root: bash gitops/sources/ca-certmate-cloudflare-mesh/tests/test_p3_secrets_syntax.sh
#
# Property 3: Required-secret substitution syntax
# For each required secret (TUNNEL_TOKEN, CLOUDFLARE_TOKEN), assert the
# docker-compose.yml file contains the pattern ${VAR:?  (colon-question-mark
# required-substitution syntax), which causes Docker Compose to fail fast with
# a descriptive error when the variable is unset rather than silently passing
# an empty string to the container.
# Validates: Requirements 5.1, 8.2, 8.3

set -euo pipefail

COMPOSE_FILE="gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

REQUIRED_SECRETS=(
  "TUNNEL_TOKEN"
  "CLOUDFLARE_TOKEN"
)

fail=0

for secret in "${REQUIRED_SECRETS[@]}"; do
  pattern="\${${secret}:?"
  if grep -qF "$pattern" "$COMPOSE_FILE"; then
    echo "PASS — '$secret' uses required-substitution syntax (\${VAR:?...})"
  else
    echo "FAIL — '$secret' does not use required-substitution syntax (\${VAR:?...}) in $COMPOSE_FILE" >&2
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "" >&2
  echo "FAIL — Property 3 (Required-secret substitution syntax): one or more secrets are missing the :? pattern" >&2
  exit 1
fi

echo "PASS — Property 3: all required secrets use required-substitution syntax"
