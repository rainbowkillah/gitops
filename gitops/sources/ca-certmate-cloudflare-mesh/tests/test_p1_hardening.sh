#!/usr/bin/env bash
# Run from the repo root: bash gitops/sources/ca-certmate-cloudflare-mesh/tests/test_p1_hardening.sh
#
# Property 1: Security hardening invariant
# For every service defined in docker-compose.yml, assert that:
#   - cap_drop contains ALL
#   - security_opt contains no-new-privileges:true
# Validates: Requirements 5.6, 6.1

set -euo pipefail

COMPOSE_FILE="gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

# Use python3 + PyYAML if available; fall back to grep-based approach
if python3 -c "import yaml" 2>/dev/null; then
  python3 - "$COMPOSE_FILE" <<'PYEOF'
import sys
import yaml

compose_file = sys.argv[1]
with open(compose_file, "r") as fh:
    doc = yaml.safe_load(fh)

services = doc.get("services", {})
if not services:
    print("ERROR: no services found in compose file", file=sys.stderr)
    sys.exit(1)

failures = []

for name, svc in services.items():
    if svc is None:
        failures.append(f"  service '{name}': definition is null/empty")
        continue

    # Check cap_drop contains ALL
    cap_drop = svc.get("cap_drop", [])
    if "ALL" not in cap_drop:
        failures.append(
            f"  service '{name}': cap_drop does not contain 'ALL' (got: {cap_drop})"
        )

    # Check security_opt contains no-new-privileges:true
    security_opt = svc.get("security_opt", [])
    if "no-new-privileges:true" not in security_opt:
        failures.append(
            f"  service '{name}': security_opt does not contain 'no-new-privileges:true' (got: {security_opt})"
        )

if failures:
    print("FAIL — Property 1 (Security hardening invariant) violations:", file=sys.stderr)
    for msg in failures:
        print(msg, file=sys.stderr)
    sys.exit(1)

service_list = ", ".join(services.keys())
print(f"PASS — Property 1: all services ({service_list}) have cap_drop=ALL and no-new-privileges:true")
PYEOF

else
  # Grep-based fallback
  echo "INFO: PyYAML not available; using grep-based fallback"
  fail=0

  # Extract service names (lines under 'services:' that are indented with 2 spaces and end with ':')
  services=$(grep -E '^  [a-zA-Z0-9_-]+:$' "$COMPOSE_FILE" | sed 's/^  //;s/://')

  if [[ -z "$services" ]]; then
    echo "ERROR: could not detect services in $COMPOSE_FILE" >&2
    exit 1
  fi

  # Check cap_drop - ALL must appear
  if ! grep -q 'cap_drop' "$COMPOSE_FILE"; then
    echo "FAIL — no cap_drop directive found in $COMPOSE_FILE" >&2
    fail=1
  elif ! grep -A5 'cap_drop' "$COMPOSE_FILE" | grep -q '\- ALL'; then
    echo "FAIL — cap_drop does not contain ALL" >&2
    fail=1
  fi

  # Check security_opt - no-new-privileges:true must appear
  if ! grep -q 'no-new-privileges:true' "$COMPOSE_FILE"; then
    echo "FAIL — security_opt does not contain 'no-new-privileges:true'" >&2
    fail=1
  fi

  if [[ $fail -eq 0 ]]; then
    echo "PASS — Property 1: cap_drop=ALL and no-new-privileges:true found (grep-based check)"
  else
    exit 1
  fi
fi
