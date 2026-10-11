#!/usr/bin/env bash
# Run from the repo root: bash gitops/sources/ca-certmate-cloudflare-mesh/tests/test_p2_volumes.sh
#
# Property 2: Volume declaration consistency
# Every volume name referenced in any service's volumes section must have a
# corresponding entry in the top-level volumes block.
# Validates: Requirements 6.5

set -euo pipefail

COMPOSE_FILE="gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

# Use python3 + PyYAML if available; fall back to grep/awk-based approach
if python3 -c "import yaml" 2>/dev/null; then
  python3 - "$COMPOSE_FILE" <<'PYEOF'
import sys
import yaml

compose_file = sys.argv[1]
with open(compose_file, "r") as fh:
    doc = yaml.safe_load(fh)

services = doc.get("services", {}) or {}
top_volumes = set((doc.get("volumes") or {}).keys())

# Collect all volume names referenced across all service volumes sections.
# Volume entries may be strings ("name:/path") or dicts with a 'source' key.
referenced = set()
for svc_name, svc in services.items():
    if not svc:
        continue
    for entry in (svc.get("volumes") or []):
        if isinstance(entry, str):
            # "volname:/container/path[:options]" or just "/host/path:/container/path"
            parts = entry.split(":")
            candidate = parts[0]
            # Named volumes don't start with '/' or './'
            if not candidate.startswith("/") and not candidate.startswith("."):
                referenced.add(candidate)
        elif isinstance(entry, dict):
            # long-form: {type: volume, source: volname, target: /path}
            if entry.get("type") == "volume" and entry.get("source"):
                referenced.add(entry["source"])

missing = referenced - top_volumes
if missing:
    print(
        "FAIL — Property 2 (Volume declaration consistency) — "
        "service volumes not declared in top-level volumes block:",
        file=sys.stderr,
    )
    for vol in sorted(missing):
        print(f"  '{vol}' is referenced in a service but missing from top-level volumes",
              file=sys.stderr)
    sys.exit(1)

if referenced:
    vol_list = ", ".join(sorted(referenced))
    print(f"PASS — Property 2: all referenced volumes ({vol_list}) are declared in top-level volumes block")
else:
    print("PASS — Property 2: no named volumes referenced in services")
PYEOF

else
  # Grep/awk-based fallback
  echo "INFO: PyYAML not available; using grep/awk-based fallback"
  fail=0

  # Extract volume references from service volumes sections (lines like "      - volname:/path")
  # Named volumes do not start with / or ./
  referenced=$(grep -E '^\s+- [^/\.].*:/' "$COMPOSE_FILE" \
    | sed 's/^\s*- //' \
    | awk -F: '{print $1}' \
    | sort -u)

  if [[ -z "$referenced" ]]; then
    echo "PASS — Property 2: no named volume references found (grep-based check)"
    exit 0
  fi

  # Extract top-level volume declarations (lines under 'volumes:' at indent level 2)
  declared=$(awk '/^volumes:/{found=1; next} found && /^  [a-zA-Z0-9_-]+:/{gsub(/:/,"",$1); print $1} found && /^[^ ]/{found=0}' "$COMPOSE_FILE" | sort -u)

  while IFS= read -r vol; do
    if ! echo "$declared" | grep -qx "$vol"; then
      echo "FAIL — volume '$vol' referenced in a service but not declared in top-level volumes block" >&2
      fail=1
    fi
  done <<< "$referenced"

  if [[ $fail -eq 0 ]]; then
    echo "PASS — Property 2: all referenced named volumes are declared in top-level volumes block (grep-based check)"
  else
    exit 1
  fi
fi
