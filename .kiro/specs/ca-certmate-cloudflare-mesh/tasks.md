# Implementation Plan: `ca-certmate-cloudflare-mesh`

## Overview

Create the GitOps stack folder for the unified CertMate + cloudflared mesh. Deliver three stack artifacts (`docker-compose.yml`, `stack.env`, `README.md`), verify the `.gitignore` covers populated env files, validate the compose file, and add property-based test scripts that verify the five correctness properties defined in the design. Explicit tasks cover the private CA web UI path (Req 4.1) and API path (Req 4.2) independently.

---

## Tasks

- [ ] 1. Create the stack folder structure
  - Create `gitops/sources/ca-certmate-cloudflare-mesh/` directory (the three files below will create it implicitly).
  - Confirm the directory mirrors the layout of `gitops/sources/cloudflare/` and `gitops/sources/certmate/`: one compose file, one env template, one README — no subdirectories.
  - _Requirements: 1.1, 1.2_

- [ ] 2. Write `docker-compose.yml`
  - [ ] 2.1 Define the CertMate service
    - Use `fabriziosalmi/certmate:${CERTMATE_VERSION:-latest}`.
    - Load environment from `stack.env` via `env_file`.
    - Reference `CLOUDFLARE_TOKEN` with `:?` required-substitution syntax (`${CLOUDFLARE_TOKEN:?Set CLOUDFLARE_TOKEN in the Portainer stack environment}`).
    - Bind port as `${CERTMATE_PORT_BIND:-127.0.0.1}:${CERTMATE_HOST_PORT:-8000}:${PORT:-8000}` (loopback-only, Req 6.2).
    - Mount all four named volumes: `certmate_data:/app/data`, `certmate_certificates:/app/certificates`, `certmate_logs:/app/logs`, `certmate_backups:/app/backups`.
    - Attach to `certmesh` network only (not the pre-existing `cloudflared` network).
    - Apply `cap_drop: [ALL]` and `security_opt: [no-new-privileges:true]`.
    - Configure health check: `["CMD", "curl", "-f", "http://localhost:${PORT:-8000}/health"]`, interval 30s, timeout 10s, retries 3, start_period 40s.
    - Configure log rotation: `driver: json-file`, `max-size: 10m`, `max-file: "3"`.
    - Set `restart: unless-stopped` and resource limits via `MEMORY_LIMIT` / `CPU_LIMIT`.
    - _Requirements: 2.3, 3.1, 3.4, 4.3, 4.4, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 8.2, 8.3_

  - [ ] 2.2 Define the cloudflared service
    - Use `cloudflare/cloudflared:${CLOUDFLARED_IMAGE_TAG:-latest}`.
    - Pass tunnel command args: `--loglevel=${TUNNEL_LOGLEVEL:-info}`, `--metrics=0.0.0.0:20241`, `--no-autoupdate`, `run`.
    - Reference `TUNNEL_TOKEN` with `:?` required-substitution syntax (`${TUNNEL_TOKEN:?Set TUNNEL_TOKEN in the Portainer stack environment}`).
    - Bind metrics port as `127.0.0.1:20241:20241`.
    - Attach to `certmesh` network only.
    - Apply `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`, `read_only: true`.
    - Configure health check: `["CMD", "cloudflared", "tunnel", "--metrics", "localhost:20241", "ready"]`, interval 30s, timeout 10s, retries 3, start_period 10s.
    - Configure log rotation: `driver: json-file`, `max-size: 10m`, `max-file: "3"`.
    - Set `restart: unless-stopped`.
    - _Requirements: 2.4, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 8.2_

  - [ ] 2.3 Declare the `certmesh` network and named volumes
    - Define `certmesh` network with `name: ${CERTMESH_NETWORK_NAME:-certmesh}`, `driver: bridge`, `external: false`.
    - Declare all four named volumes (`certmate_data`, `certmate_certificates`, `certmate_logs`, `certmate_backups`) with `driver: local`.
    - Ensure neither service references the pre-existing `cloudflared` network.
    - _Requirements: 2.1, 2.2, 2.5, 6.5_

- [ ] 3. Write `stack.env` template
  - [ ] 3.1 Document all non-secret variables with defaults
    - Include `CERTMATE_VERSION`, `CLOUDFLARED_IMAGE_TAG`, `CERTMESH_NETWORK_NAME`, `CERTMATE_PORT_BIND`, `CERTMATE_HOST_PORT`, `PORT`, `MEMORY_LIMIT`, `CPU_LIMIT`, `TUNNEL_LOGLEVEL`, and `LETSENCRYPT_EMAIL` (required placeholder — operator must replace with a registered ACME email).
    - Set `GUNICORN_TIMEOUT=300` (minimum 300; comment explains DNS propagation requirement).
    - Each variable SHALL have either a sensible default value or an inline comment explaining what to set.
    - _Requirements: 1.4, 3.5, 7.4_

  - [ ] 3.2 Add secret variables with empty values and Portainer UI instructions
    - Add `TUNNEL_TOKEN=`, `CLOUDFLARE_TOKEN=`, `API_BEARER_TOKEN=`, `SECRET_KEY=`, `CERTMATE_BACKUP_PASSPHRASE=` each with empty string values.
    - Each secret SHALL have a comment directing the operator to supply the value via the Portainer stack environment UI and to never commit a populated value.
    - _Requirements: 1.4, 4.5, 8.1_

- [ ] 4. Write `README.md`
  - Cover: pre-deployment checklist (create Cloudflare tunnel, obtain API tokens, set `LETSENCRYPT_EMAIL`), step-by-step Portainer stack creation, required secret values and where to obtain each one, network topology diagram (ASCII), volume management notes (fresh vs. re-using existing certmate volumes), private CA usage notes (web UI path per Req 4.1; API path per Req 4.2), and rollback procedure.
  - _Requirements: 1.5, 4.1, 4.2_

- [ ] 5. Verify private CA accessibility — web UI path (Req 4.1)
  - [ ] 5.1 Add a compose-level label or comment in `docker-compose.yml` confirming the CertMate web UI port binding exposes the private CA dashboard
    - Confirm the bound port (`${CERTMATE_PORT_BIND:-127.0.0.1}:${CERTMATE_HOST_PORT:-8000}`) makes the UI reachable at `http://127.0.0.1:8000` for an operator to issue internal certificates interactively.
    - Add a comment block in `docker-compose.yml` (above the certmate service) that documents the web UI URL and notes that private CA certificate issuance is available via the browser UI at this address.
    - _Requirements: 4.1_

  - [ ] 5.2 Document the web UI private CA workflow in `README.md`
    - Add a dedicated "Private CA — Web UI" section in `README.md` describing how an operator navigates to `http://127.0.0.1:8000`, locates the Private CA section, and issues a certificate for an internal service name (e.g. `host.docker.internal`).
    - _Requirements: 4.1_

- [ ] 6. Verify private CA accessibility — API path (Req 4.2)
  - [ ] 6.1 Add a comment block in `docker-compose.yml` documenting the CertMate API endpoint for internal certificate issuance
    - Document the API endpoint pattern (`POST /api/certificates` with `API_BEARER_TOKEN`) so automated tooling can issue internal certs without using the UI.
    - _Requirements: 4.2_

  - [ ] 6.2 Document the API private CA workflow in `README.md`
    - Add a dedicated "Private CA — API" section in `README.md` with an example `curl` command that issues an internal certificate for `host.docker.internal` via the `API_BEARER_TOKEN`-authenticated endpoint.
    - _Requirements: 4.2, 4.3_

- [ ] 7. Checkpoint — validate compose file and gitignore
  - Run `docker compose -f gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml config --quiet` from the repo root to verify the file parses without errors.
  - Confirm that `.gitignore` at the repo root covers env files in the gitops tree. The current `.gitignore` only excludes `.env` at the root; add a `gitops/**/*.env` pattern so all stack env files are excluded from tracking when populated by operators.
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 1.3, 8.4_

- [ ] 8. Add property-based test scripts
  - [ ] 8.1 Write test script for Property 1 — Security hardening invariant
    - Parse `gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml`.
    - For every service defined, assert `cap_drop` contains `ALL` and `security_opt` contains `no-new-privileges:true`.
    - **Property 1: Security hardening invariant**
    - **Validates: Requirements 5.6, 6.1**

  - [ ] 8.2 Write test script for Property 2 — Volume declaration consistency
    - Parse the compose file.
    - Collect every volume name referenced in any service's `volumes` section.
    - Assert each collected name has a corresponding entry in the top-level `volumes` block.
    - **Property 2: Volume declaration consistency**
    - **Validates: Requirements 6.5**

  - [ ] 8.3 Write test script for Property 3 — Required-secret substitution syntax
    - Read `docker-compose.yml` as raw text.
    - For each required secret (`TUNNEL_TOKEN`, `CLOUDFLARE_TOKEN`), assert the file contains the pattern `${VAR:?` (colon-question-mark required-substitution syntax).
    - **Property 3: Required-secret substitution syntax**
    - **Validates: Requirements 5.1, 8.2, 8.3**

  - [ ] 8.4 Write test script for Property 4 — Committed stack.env has empty secret values
    - Parse `gitops/sources/ca-certmate-cloudflare-mesh/stack.env` line by line.
    - For each secret variable (`TUNNEL_TOKEN`, `CLOUDFLARE_TOKEN`, `API_BEARER_TOKEN`, `SECRET_KEY`, `CERTMATE_BACKUP_PASSPHRASE`), assert the assigned value is the empty string.
    - **Property 4: Committed stack.env contains no secret values**
    - **Validates: Requirements 8.1**

  - [ ] 8.5 Write test script for Property 5 — GUNICORN_TIMEOUT ≥ 300
    - Parse `stack.env` and extract the value of `GUNICORN_TIMEOUT`.
    - Assert the value is a parseable non-negative integer and is greater than or equal to 300.
    - **Property 5: Gunicorn timeout is sufficient for DNS propagation**
    - **Validates: Requirements 7.4**

  - [ ] 8.6 Place all test scripts under `gitops/sources/ca-certmate-cloudflare-mesh/tests/` and add a short runner comment at the top of each file explaining how to execute it (e.g., `bash tests/test_p1_hardening.sh`).
    - _Requirements: 1.1_

- [ ] 9. Final checkpoint — Ensure all tests pass
  - Run all five property test scripts and confirm they exit 0.
  - Ensure all tests pass, ask the user if questions arise.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP.
- Each task references specific requirements for traceability.
- Requirement 4.1 (web UI) is covered by tasks 5.1 and 5.2; Requirement 4.2 (API) is covered by tasks 6.1 and 6.2 — these are intentionally separate so each path can be reviewed and tested independently.
- Property tests (tasks 8.1–8.5) validate the universal correctness properties from `design.md §8`.
- The `.gitignore` fix in task 7 is important: the current root `.gitignore` only excludes `.env` at the repo root. The pattern `gitops/**/*.env` must be added so operators can safely populate a local `stack.env` without accidentally committing secrets.
- `CERTMATE_BACKUP_PASSPHRASE` (Req 4.5) is included in the secret block of `stack.env` alongside the other four secrets.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["2.1", "2.2", "2.3", "3.1", "3.2"] },
    { "id": 1, "tasks": ["4.1", "5.1", "5.2", "6.1", "6.2"] },
    { "id": 2, "tasks": ["7.1", "8.1", "8.2", "8.3", "8.4", "8.5", "8.6"] }
  ]
}
```
