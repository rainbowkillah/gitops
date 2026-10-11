# Design Document

## Feature: `ca-certmate-cloudflare-mesh`

---

## 1. High-Level Architecture

The stack composes three concerns into a single GitOps-managed unit:

```
┌──────────────────────────────────────────────────────────────┐
│  Portainer Edge Agent                                        │
│  reads docker-compose.yml + stack.env from Git               │
│  applies stack to Docker Desktop / WSL host                  │
└───────────────────────┬──────────────────────────────────────┘
                        │ deploys
          ┌─────────────▼──────────────────┐
          │       certmesh (bridge)        │
          │                                │
          │  ┌────────────┐  ┌──────────┐  │
          │  │  certmate  │  │cloudflared│  │
          │  │  :8000     │◄─┤  :20241  │  │
          │  └────────────┘  └──────────┘  │
          └────────────────────────────────┘
                 │                  │
           [host loopback]   [Cloudflare Edge]
           127.0.0.1:8000    (outbound tunnel)
           (mgmt UI)
```

**CertMate** (`fabriziosalmi/certmate`) serves a dual role:
- **Public CA client** — performs Cloudflare DNS-01 ACME challenges to obtain Let's Encrypt certificates for `rainbowsmokeofficial.com` and `mrrainbowsmoke.com`.
- **Private CA** — issues certificates for internal service names (`host.docker.internal`, other mesh services) from its own self-signed root, with no external ACME interaction.

**cloudflared** (`cloudflare/cloudflared`) maintains an outbound tunnel to the Cloudflare edge. It resolves origins by container service name on the `certmesh` network (e.g. `http://certmate:8000`), so no static IP configuration is needed.

**Portainer Edge Agent** applies the stack definition from `gitops/sources/ca-certmate-cloudflare-mesh/` via GitOps pull. Secrets are never stored in source control; the operator injects them through the Portainer stack environment UI.

---

## 2. Component Design

### 2.1 Stack Folder Layout

```
gitops/sources/ca-certmate-cloudflare-mesh/
├── docker-compose.yml   # service definitions, network, volumes
├── stack.env            # documented template; secrets are empty
└── README.md            # deployment steps, secrets reference, topology
```

This mirrors the existing `gitops/sources/cloudflare/` and `gitops/sources/certmate/` convention: one compose file and one env template per stack, no subdirectories.

### 2.2 CertMate Service Definition

```yaml
services:
  certmate:
    image: fabriziosalmi/certmate:${CERTMATE_VERSION:-latest}
    restart: unless-stopped
    env_file:
      - stack.env
    environment:
      CLOUDFLARE_TOKEN: ${CLOUDFLARE_TOKEN:?Set CLOUDFLARE_TOKEN in the Portainer stack environment}
    ports:
      - "${CERTMATE_PORT_BIND:-127.0.0.1}:${CERTMATE_HOST_PORT:-8000}:${PORT:-8000}"
    volumes:
      - certmate_data:/app/data
      - certmate_certificates:/app/certificates
      - certmate_logs:/app/logs
      - certmate_backups:/app/backups
    networks:
      - certmesh
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${PORT:-8000}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: ${MEMORY_LIMIT:-512m}
          cpus: "${CPU_LIMIT:-1.0}"
```

Key differences from the standalone `certmate` stack:
- Added to `certmesh` network only (no `cloudflared` network).
- `CLOUDFLARE_TOKEN` uses `:?` required-substitution so the stack fails fast if the token is absent.
- All four named volumes carried over unchanged for persistence continuity.

### 2.3 cloudflared Service Definition

```yaml
  cloudflared:
    image: cloudflare/cloudflared:${CLOUDFLARED_IMAGE_TAG:-latest}
    restart: unless-stopped
    command:
      - tunnel
      - --loglevel=${TUNNEL_LOGLEVEL:-info}
      - --metrics=0.0.0.0:20241
      - --no-autoupdate
      - run
    environment:
      TUNNEL_TOKEN: ${TUNNEL_TOKEN:?Set TUNNEL_TOKEN in the Portainer stack environment}
    ports:
      - "127.0.0.1:20241:20241"
    networks:
      - certmesh
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    read_only: true
    healthcheck:
      test: ["CMD", "cloudflared", "tunnel", "--metrics", "localhost:20241", "ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

Key differences from the standalone `cloudflare` stack:
- Network is `certmesh` instead of `cloudflared` — the two stacks are fully isolated.
- Metrics port remains `127.0.0.1:20241` on the host; the `--metrics` flag binds `0.0.0.0:20241` inside the container so the healthcheck can reach it from `localhost`.

### 2.4 Network and Volume Declarations

```yaml
networks:
  certmesh:
    name: ${CERTMESH_NETWORK_NAME:-certmesh}
    driver: bridge
    external: false

volumes:
  certmate_data:
    driver: local
  certmate_certificates:
    driver: local
  certmate_logs:
    driver: local
  certmate_backups:
    driver: local
```

All volumes are scoped to this stack. If the standalone `certmate` stack has been run previously, the operator can point these volumes at the existing ones by setting their names in `stack.env`; otherwise fresh volumes are created.

---

## 3. Network Topology

```
Host (Docker Desktop / WSL)
│
├─ 127.0.0.1:8000   ──► certmate:8000       (CertMate management UI, loopback only)
├─ 127.0.0.1:20241  ──► cloudflared:20241   (Prometheus metrics, loopback only)
│
└─ certmesh (bridge, 172.x.x.0/24)
       ├── certmate        (service name resolvable within certmesh)
       └── cloudflared     (routes origins by service name, e.g. http://certmate:8000)

External
└─ Cloudflare Edge  ◄──── cloudflared (outbound QUIC/HTTP2 tunnel, no inbound ports)
└─ Let's Encrypt    ◄──── CertMate (HTTPS to ACME API, DNS-01 TXT record via Cloudflare API)
```

Neither service is attached to the pre-existing `cloudflared` bridge network. The two stacks are completely network-isolated. If a future stack needs to reach CertMate, it joins `certmesh` rather than the tunnel stack's network.

---

## 4. Certificate Issuance Flows

### 4.1 Public Domain (DNS-01 via Let's Encrypt)

```
CertMate scheduler
  │
  ├─ detects cert for rainbowsmokeofficial.com or mrrainbowsmoke.com
  │  is within renewal window (default: 30 days before expiry)
  │
  ├─ calls Cloudflare API (CLOUDFLARE_TOKEN)
  │    POST /zones/{zone_id}/dns_records
  │    type=TXT  name=_acme-challenge.<domain>  content=<token>
  │
  ├─ notifies Let's Encrypt ACME endpoint
  │    POST /acme/challenge
  │
  ├─ Let's Encrypt queries DNS, validates TXT record
  │
  ├─ calls Cloudflare API to delete TXT record
  │
  └─ writes new cert + key to /app/certificates  (certmate_certificates volume)
```

`GUNICORN_TIMEOUT` is set to ≥ 300 seconds in `stack.env` to accommodate slow DNS propagation before the worker process times out.

### 4.2 Private CA (Internal Services)

```
Client (internal service or operator)
  │
  ├─ POST /api/certificates  { "domain": "host.docker.internal", "type": "internal" }
  │    (authenticated with API_BEARER_TOKEN)
  │
  ├─ CertMate issues cert from its local private CA root
  │    (no external ACME contact)
  │
  └─ writes cert + key to /app/certificates  (certmate_certificates volume)
```

The private CA root is generated on first startup and persisted in `certmate_data`. Clients that need to trust these certificates must install the CA root separately.

---

## 5. Security Design

### 5.1 Container Hardening

Both services apply the same baseline:

| Control | Value | Rationale |
|---|---|---|
| `cap_drop` | `ALL` | Remove all Linux capabilities; neither service needs any |
| `security_opt` | `no-new-privileges:true` | Prevent privilege escalation via setuid/setgid |
| `read_only` | `true` (cloudflared only) | cloudflared needs no writable filesystem; CertMate writes to mounted volumes |
| Port binding | `127.0.0.1:*` | Management UI and metrics never exposed on external interfaces |
| `restart` | `unless-stopped` | Automatic recovery; operator-initiated stops are respected |

### 5.2 Secret Management

Secrets are managed through a two-layer approach:

**Layer 1 — Template stack.env (committed to Git):**
```env
# Secrets — supply via Portainer stack environment UI, never commit values
TUNNEL_TOKEN=
CLOUDFLARE_TOKEN=
API_BEARER_TOKEN=
SECRET_KEY=
CERTMATE_BACKUP_PASSPHRASE=
```

All five secrets have empty string values. The operator pastes real values into the Portainer stack environment variables screen at deploy time; Portainer merges them into the container environment at runtime.

**Layer 2 — Compose required-substitution:**
```yaml
TUNNEL_TOKEN: ${TUNNEL_TOKEN:?Set TUNNEL_TOKEN in the Portainer stack environment}
CLOUDFLARE_TOKEN: ${CLOUDFLARE_TOKEN:?Set CLOUDFLARE_TOKEN in the Portainer stack environment}
```

The `:?` syntax causes `docker compose` to exit with a descriptive error if either variable resolves to empty, preventing a misconfigured deployment from silently running with no authentication.

**Layer 3 — .gitignore:**
The repository root `.gitignore` already contains `*.env` exclusions. The committed `stack.env` is a documented template only; no populated secret file is ever staged.

---

## 6. GitOps Deployment Flow

```
Git repository (v:\Docker\portainer)
  └── gitops/sources/ca-certmate-cloudflare-mesh/
        ├── docker-compose.yml
        ├── stack.env          (template, secrets empty)
        └── README.md

Portainer Edge Agent
  1. Polls Git for changes to gitops/sources/ca-certmate-cloudflare-mesh/
  2. Reads docker-compose.yml
  3. Merges stack.env template with operator-supplied secret values from Portainer UI
  4. Runs docker compose up -d --remove-orphans
  5. Health checks become healthy → stack reports Running
```

The `README.md` covers:
- Pre-deployment checklist (create Cloudflare tunnel, obtain API token, set LETSENCRYPT_EMAIL)
- Step-by-step Portainer stack creation
- Required secret values and where to obtain them
- Network topology diagram
- Volume management notes (fresh vs existing certmate volumes)
- Rollback procedure

---

## 7. Error Handling

| Scenario | Behaviour |
|---|---|
| `TUNNEL_TOKEN` not set | `docker compose` exits with required-substitution error before any container starts |
| `CLOUDFLARE_TOKEN` not set | `docker compose` exits with required-substitution error before any container starts |
| DNS-01 challenge timeout | CertMate logs domain name, error message, and timestamp; `GUNICORN_TIMEOUT=300` prevents worker kill before propagation |
| CertMate health check fails | Docker restarts container after 3 retries (90s window); `restart: unless-stopped` handles transient failures |
| cloudflared loses tunnel | cloudflared retries with exponential backoff (`TUNNEL_RETRIES=5`); health check `/ready` returns non-200 until reconnected; Docker does not restart during reconnect attempts |
| Container OOM | `memory: 512m` limit causes Docker to kill and restart the certmate container; all state is in named volumes |

---

## 8. Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Security hardening invariant

*For any* service defined in `docker-compose.yml`, that service SHALL include `cap_drop: [ALL]` and `security_opt: [no-new-privileges:true]` in its definition.

**Validates: Requirements 5.6, 6.1**

---

### Property 2: Volume declaration consistency

*For any* volume name referenced in a service's `volumes` section of `docker-compose.yml`, a corresponding top-level entry SHALL exist in the `volumes` block of the same file.

**Validates: Requirements 6.5**

---

### Property 3: Required-secret substitution syntax

*For any* variable in the required-secrets set (`TUNNEL_TOKEN`, `CLOUDFLARE_TOKEN`), the compose file SHALL reference it using the `${VAR:?<message>}` required-substitution syntax, ensuring stack deployment fails with a descriptive error when the variable is unset or empty.

**Validates: Requirements 5.1, 8.2, 8.3**

---

### Property 4: Committed stack.env contains no secret values

*For any* variable name in the secret set (`TUNNEL_TOKEN`, `CLOUDFLARE_TOKEN`, `API_BEARER_TOKEN`, `SECRET_KEY`, `CERTMATE_BACKUP_PASSPHRASE`), its assigned value in the committed `stack.env` SHALL be the empty string.

**Validates: Requirements 8.1**

---

### Property 5: Gunicorn timeout is sufficient for DNS propagation

*For any* `stack.env` file deployed by this stack, the value assigned to `GUNICORN_TIMEOUT` SHALL be parseable as a non-negative integer and SHALL be greater than or equal to 300.

**Validates: Requirements 7.4**
