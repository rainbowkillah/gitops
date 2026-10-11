# ca-certmate-cloudflare-mesh

Unified CertMate + cloudflared stack on a dedicated `certmesh` bridge network.
CertMate serves a dual role: it issues publicly-trusted Let's Encrypt certificates
for `rainbowsmokeofficial.com` and `mrrainbowsmoke.com` via Cloudflare DNS-01, and
it operates as a private CA for internal mesh services (e.g. `host.docker.internal`).
cloudflared routes public traffic from the Cloudflare edge to CertMate by container
service name on the shared `certmesh` network.

---

## Table of Contents

1. [Pre-deployment checklist](#1-pre-deployment-checklist)
2. [Step-by-step Portainer stack creation](#2-step-by-step-portainer-stack-creation)
3. [Required secrets and where to obtain them](#3-required-secrets-and-where-to-obtain-them)
4. [Network topology](#4-network-topology)
5. [Volume management](#5-volume-management)
6. [Private CA usage](#6-private-ca-usage) — [Web UI](#61-private-ca--web-ui) · [API](#62-private-ca--api)
7. [Rollback procedure](#7-rollback-procedure)

---

## 1. Pre-deployment checklist

Complete every item before deploying the stack. A missing value causes a hard
start failure for secrets marked `:?` and silent misconfiguration for others.

### 1.1 Cloudflare Tunnel

- [ ] Log in to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) > **Networks > Tunnels**.
- [ ] Create a new tunnel (type: Cloudflared). Give it a descriptive name, e.g. `certmesh`.
- [ ] In the tunnel detail page select **Add a replica** and copy the tunnel token.
      This value becomes `TUNNEL_TOKEN`.
- [ ] Configure at least one public hostname for the tunnel, e.g.
      `certmate.rainbowsmokeofficial.com → http://certmate:8000`.

### 1.2 Cloudflare API token

- [ ] Go to [Cloudflare dashboard](https://dash.cloudflare.com/) > **My Profile > API Tokens > Create Token**.
- [ ] Start from the **Edit zone DNS** template.
- [ ] Scope the token to the zones `rainbowsmokeofficial.com` and `mrrainbowsmoke.com`.
- [ ] Copy the generated token. This value becomes `CLOUDFLARE_TOKEN`.

### 1.3 LETSENCRYPT_EMAIL

- [ ] Decide which email address should receive Let's Encrypt expiry notifications.
- [ ] Update `LETSENCRYPT_EMAIL` in `stack.env` **or** set it as an environment variable
      in the Portainer stack UI before deploying.
- [ ] The address must be reachable; Let's Encrypt sends renewal warnings to it.

### 1.4 Remaining secrets

- [ ] Generate `API_BEARER_TOKEN` — a random 32-byte hex string:
      ```bash
      openssl rand -hex 32
      ```
- [ ] Generate `SECRET_KEY` — a separate random 32-byte hex string:
      ```bash
      openssl rand -hex 32
      ```
- [ ] Choose a `CERTMATE_BACKUP_PASSPHRASE` for encrypted backup archives.
- [ ] Keep all generated values in a password manager. They are never committed to git.

### 1.5 Docker / Portainer prerequisites

- [ ] Docker Desktop (or Docker Engine) is running on the target host.
- [ ] Portainer is deployed and the Edge Agent can reach the GitOps repository.
- [ ] Port `8000` is free on `127.0.0.1` (or choose an alternative via `CERTMATE_HOST_PORT`).

---

## 2. Step-by-step Portainer stack creation

### Option A — GitOps (recommended)

1. In Portainer, go to **Stacks > Add stack**.
2. Select **Repository** as the build method.
3. Set the repository URL to this repo and the compose file path to:
   ```
   gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml
   ```
4. Enable **Automatic updates** if you want Portainer Edge Agent to redeploy on
   git push.
5. Switch to the **Environment variables** tab.
6. Add each secret from [Section 3](#3-required-secrets-and-where-to-obtain-them) as
   a key/value pair. Do **not** commit populated values to the repository.
7. Click **Deploy the stack**.

### Option B — manual compose upload

1. In Portainer, go to **Stacks > Add stack > Upload**.
2. Upload `docker-compose.yml`.
3. In the **Environment variables** section, add all secrets and any overrides.
4. Click **Deploy the stack**.

### Verifying a successful deployment

After the stack starts, confirm both containers are healthy:

```bash
# From the Docker host
docker ps --filter "label=com.docker.compose.project=ca-certmate-cloudflare-mesh"

# CertMate health endpoint
curl -sf http://127.0.0.1:8000/health && echo "CertMate OK"

# cloudflared metrics / ready endpoint
curl -sf http://127.0.0.1:20241/ready && echo "cloudflared OK"
```

Both should return without error within 60 seconds of deploy.

---

## 3. Required secrets and where to obtain them

All five secrets must be supplied through the Portainer stack environment UI.
**Never commit a populated value to source control.**

| Variable | Purpose | Where to obtain |
|---|---|---|
| `TUNNEL_TOKEN` | Authenticates cloudflared to the Cloudflare edge | Cloudflare Zero Trust > Networks > Tunnels > your tunnel > Add a replica |
| `CLOUDFLARE_TOKEN` | Allows CertMate to create DNS TXT records for DNS-01 ACME challenges | Cloudflare dashboard > My Profile > API Tokens > Create Token (Edit zone DNS template, scoped to target zones) |
| `API_BEARER_TOKEN` | Protects all CertMate API endpoints | Generate locally: `openssl rand -hex 32` |
| `SECRET_KEY` | Signs Flask session cookies for the CertMate web UI | Generate locally: `openssl rand -hex 32` |
| `CERTMATE_BACKUP_PASSPHRASE` | Encrypts automatic backup archives | Choose a strong passphrase; store in a password manager |

### Token scope requirements

**CLOUDFLARE_TOKEN** minimum permissions:
- Zone → DNS → Edit
- Zone Resources → Include → Specific zone → `rainbowsmokeofficial.com`
- Zone Resources → Include → Specific zone → `mrrainbowsmoke.com`

A narrower scope than DNS Edit will cause DNS-01 challenges to fail silently.

---

## 4. Network topology

```
                          ┌─────────────────────────────────────────────┐
                          │  certmesh  (Docker bridge, driver: bridge)   │
                          │                                               │
  ┌───────────────────┐   │  ┌─────────────┐     ┌────────────────────┐ │
  │  Docker host      │   │  │  certmate   │     │   cloudflared      │ │
  │  127.0.0.1:8000 ──┼───┼──│  :8000      │     │   (outbound only)  │ │
  │  127.0.0.1:20241 ─┼───┼──│─────────────┼─────│   :20241 metrics   │ │
  └───────────────────┘   │  └─────────────┘     └────────┬───────────┘ │
                          └──────────────────────────────┼──────────────┘
                                                         │  outbound TLS tunnel
                                                         ▼
                                              ┌──────────────────────┐
                                              │  Cloudflare edge     │
                                              │  (Zero Trust)        │
                                              └──────────┬───────────┘
                                                         │
                                                         ▼  public DNS
                                              rainbowsmokeofficial.com
                                              mrrainbowsmoke.com
```

**Key points:**

- Both containers are attached **only** to `certmesh`. Neither touches the
  pre-existing `cloudflared` bridge network, keeping the two stacks isolated.
- CertMate's port `8000` is bound to `127.0.0.1` (loopback only). It is
  **not** reachable from outside the host unless cloudflared routes traffic to it.
- cloudflared reaches CertMate by Docker service name: `http://certmate:8000`.
- The cloudflared metrics port `20241` is also loopback-only.
- All outbound tunnel traffic originates from cloudflared; no inbound ports are
  published for cloudflared.

---

## 5. Volume management

This stack declares four named volumes, all scoped to the `ca-certmate-cloudflare-mesh`
project:

| Volume | Mount path | Contents |
|---|---|---|
| `certmate_data` | `/app/data` | CertMate database, scheduler state, configuration |
| `certmate_certificates` | `/app/certificates` | Issued certificates (public and private CA) |
| `certmate_logs` | `/app/logs` | Application logs |
| `certmate_backups` | `/app/backups` | Encrypted backup archives |

### Fresh deployment

When the stack is deployed for the first time, Docker creates all four volumes
automatically. No action is required.

### Re-using volumes from a standalone certmate stack

If you previously ran a standalone `certmate` stack, its volumes are named
differently (typically `certmate_certmate_data`, etc., depending on the project
name). To migrate:

1. Stop the old stack in Portainer.
2. Copy the old volume contents into the new volumes. Example for `certmate_data`:
   ```bash
   docker run --rm \
     -v certmate_certmate_data:/from:ro \
     -v ca-certmate-cloudflare-mesh_certmate_data:/to \
     alpine sh -c "cp -av /from/. /to/"
   ```
3. Repeat for `certmate_certificates`, `certmate_logs`, and `certmate_backups`.
4. Deploy this stack. CertMate will start with the existing database and
   certificates intact.
5. Once you confirm everything works, remove the old standalone stack and
   optionally prune its now-unused volumes:
   ```bash
   docker volume rm certmate_certmate_data certmate_certmate_certificates \
                    certmate_certmate_logs certmate_certmate_backups
   ```

### Preventing accidental data loss

- Do **not** run `docker compose down -v` unless you intend to delete all certificate
  data. Use `docker compose down` (without `-v`) to stop the stack while preserving volumes.
- Take a backup before any major update:
  ```bash
  # Trigger a manual backup via the CertMate API
  curl -sf -X POST http://127.0.0.1:8000/api/backup \
    -H "Authorization: Bearer $API_BEARER_TOKEN"
  ```
  The archive is stored in `certmate_backups` and encrypted with `CERTMATE_BACKUP_PASSPHRASE`.

---

## 6. Private CA usage

CertMate runs a built-in private CA for issuing certificates to internal services
that cannot be validated by a public ACME authority (e.g. `host.docker.internal`,
other mesh container service names).

Both paths below produce certificates signed by the same private CA root.
Trust the CA root in any client that needs to verify these certificates.

---

### 6.1 Private CA — Web UI

The CertMate web UI is accessible at **`http://127.0.0.1:8000`** from the Docker
host (loopback-only binding; see §4 for why). No API token is required for
browser-based interaction — authentication is handled by the Flask session signed
with `SECRET_KEY`.

#### Prerequisites

- The stack is deployed and CertMate's health check is green (see §2).
- You are working at a browser **on the Docker host** (or have an SSH port-forward
  from a remote machine: `ssh -L 8000:127.0.0.1:8000 <host>`).

#### Step-by-step: issue an internal certificate

1. **Open the UI.** Navigate to `http://127.0.0.1:8000` in a browser.

2. **Log in.** Enter your CertMate credentials. The session is signed with
   `SECRET_KEY`; no separate API token is needed here.

3. **Go to the Private CA section.** In the left-hand sidebar look for
   **Private CA** or **Certificates → Internal**. The exact label depends on
   the CertMate version deployed.

4. **Click "Issue certificate"** (or "New certificate" / "Generate").

5. **Fill in the certificate details:**

   | Field | Example value | Notes |
   |---|---|---|
   | Common Name | `host.docker.internal` | The primary DNS name the cert will be valid for |
   | Subject Alternative Names | `host.docker.internal` | Add extra names here if needed (comma-separated or one per line) |
   | Validity period | `365` (days) | Leave at the default unless a shorter lifetime is required |
   | Key type | `RSA 2048` or `ECDSA P-256` | Either is fine for internal use |

   Other internal service names that work here:
   - `certmate.internal`
   - `myservice.certmesh`
   - `<container-service-name>` (any name routable inside the `certmesh` network)

6. **Click "Generate".** CertMate issues the certificate using the local private
   CA root, stores the key pair in the `certmate_certificates` named volume, and
   presents the certificate and private key for download.

7. **Download the files.** Save both the `.crt` and `.key` files. The private key
   is shown only once; if you lose it you must re-issue the certificate.

#### Trusting the private CA root in other services

Any client that needs to verify certificates signed by this CA must trust the CA
root certificate. To retrieve it:

1. In the CertMate UI, navigate to **Private CA → Root Certificate** (or
   **Settings → CA**).
2. Download `ca.crt`.
3. Install it in the trust store of the relevant client:
   - **Linux (system-wide):**
     ```bash
     sudo cp ca.crt /usr/local/share/ca-certificates/certmate-ca.crt
     sudo update-ca-certificates
     ```
   - **curl / custom tooling:** pass `--cacert ca.crt` or set `SSL_CERT_FILE`.
   - **Another container:** mount `ca.crt` into the container and add it to that
     image's trust store at build or start time.

#### Renewal of internal certificates

Internal certificates do not use DNS-01; CertMate renews them automatically
using the same private CA root before they expire. No manual renewal steps are
needed as long as the stack is running and the `certmate_data` volume is intact
(it holds the scheduler state).

---

### 6.2 Private CA — API

The CertMate API is available at `http://127.0.0.1:8000/api/` and uses
`API_BEARER_TOKEN` for authentication. Use this path from automated tooling,
CI pipelines, or other containers on `certmesh`.

**Issue an internal certificate:**

```bash
curl -sf -X POST http://127.0.0.1:8000/api/certificates \
  -H "Authorization: Bearer $API_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain": "host.docker.internal", "type": "internal"}' \
  | jq .
```

**Issue a certificate with SANs:**

```bash
curl -sf -X POST http://127.0.0.1:8000/api/certificates \
  -H "Authorization: Bearer $API_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "myservice.certmesh",
    "type": "internal",
    "san": ["myservice.certmesh", "myservice", "127.0.0.1"]
  }' \
  | jq .
```

**List issued certificates:**

```bash
curl -sf http://127.0.0.1:8000/api/certificates \
  -H "Authorization: Bearer $API_BEARER_TOKEN" \
  | jq .
```

**Retrieve the private CA root certificate via API:**

```bash
curl -sf http://127.0.0.1:8000/api/ca/root \
  -H "Authorization: Bearer $API_BEARER_TOKEN" \
  -o ca.crt
```

---

## 7. Rollback procedure

Use this procedure if the stack fails to start, or if a deployed update introduces
a regression.

### 7.1 Roll back to the previous git revision

1. Identify the last known-good commit:
   ```bash
   git log --oneline gitops/sources/ca-certmate-cloudflare-mesh/
   ```
2. Check out the stack files at that commit without changing HEAD:
   ```bash
   git checkout <commit-sha> -- \
     gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml \
     gitops/sources/ca-certmate-cloudflare-mesh/stack.env
   ```
3. Commit the revert:
   ```bash
   git add gitops/sources/ca-certmate-cloudflare-mesh/
   git commit -m "revert: roll back ca-certmate-cloudflare-mesh to <commit-sha>"
   git push
   ```
4. In Portainer, trigger a manual pull/redeploy of the stack, or wait for the
   Edge Agent to pick up the new commit if automatic updates are enabled.

### 7.2 Force redeploy in Portainer (no git change needed)

If the stack is in a bad state but the compose file is correct:

1. In Portainer, open the stack **ca-certmate-cloudflare-mesh**.
2. Click **Update the stack** > enable **Re-pull image** if an image regression
   is suspected.
3. Click **Update**.

### 7.3 Stop the stack without removing volumes

To stop all containers while preserving certificate data and config:

```bash
# From the Docker host, in the repo root
docker compose \
  -f gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml \
  --env-file gitops/sources/ca-certmate-cloudflare-mesh/stack.env \
  down
```

Do **not** add the `-v` flag. Removing volumes deletes all issued certificates
and CertMate state.

### 7.4 Full teardown (destructive)

Only use this if you intend to start completely fresh.

```bash
docker compose \
  -f gitops/sources/ca-certmate-cloudflare-mesh/docker-compose.yml \
  --env-file gitops/sources/ca-certmate-cloudflare-mesh/stack.env \
  down -v
```

This removes all four named volumes. **Certificate data cannot be recovered
unless a backup exists in `certmate_backups` and `CERTMATE_BACKUP_PASSPHRASE`
is known.**

### 7.5 Restore from backup

If you have a backup archive from `certmate_backups`:

1. Deploy the stack fresh (volumes will be empty).
2. Copy the backup archive into the running container:
   ```bash
   docker cp certmate-backup.tar.gz \
     $(docker ps -qf name=certmate):/app/backups/
   ```
3. Trigger a restore via the CertMate API:
   ```bash
   curl -sf -X POST http://127.0.0.1:8000/api/restore \
     -H "Authorization: Bearer $API_BEARER_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"filename": "certmate-backup.tar.gz", "passphrase": "<CERTMATE_BACKUP_PASSPHRASE>"}'
   ```
4. Restart the stack to let CertMate reload its state from the restored volume.

---

## Reference

### Environment variables quick reference

| Variable | Default | Required | Notes |
|---|---|---|---|
| `CERTMATE_VERSION` | `latest` | No | Pin to a specific tag in production |
| `CLOUDFLARED_IMAGE_TAG` | `latest` | No | Pin to a specific tag in production |
| `CERTMESH_NETWORK_NAME` | `certmesh` | No | Override to avoid name collisions |
| `CERTMATE_PORT_BIND` | `127.0.0.1` | No | Change to `0.0.0.0` only if no tunnel in front |
| `CERTMATE_HOST_PORT` | `8000` | No | Host port for CertMate UI |
| `PORT` | `8000` | No | Container-internal port |
| `MEMORY_LIMIT` | `512m` | No | Docker resource limit for CertMate |
| `CPU_LIMIT` | `1.0` | No | Docker CPU limit for CertMate |
| `TUNNEL_LOGLEVEL` | `info` | No | `debug` exposes request details — avoid in production |
| `LETSENCRYPT_EMAIL` | *(must set)* | **Yes** | Valid email for ACME expiry notifications |
| `GUNICORN_TIMEOUT` | `300` | No | Minimum 300 — required for DNS propagation |
| `TUNNEL_TOKEN` | *(empty)* | **Yes** | Supply via Portainer UI only |
| `CLOUDFLARE_TOKEN` | *(empty)* | **Yes** | Supply via Portainer UI only |
| `API_BEARER_TOKEN` | *(empty)* | **Yes** | Supply via Portainer UI only |
| `SECRET_KEY` | *(empty)* | **Yes** | Supply via Portainer UI only |
| `CERTMATE_BACKUP_PASSPHRASE` | *(empty)* | **Yes** | Supply via Portainer UI only |

### Useful endpoints

| Endpoint | Description |
|---|---|
| `http://127.0.0.1:8000/` | CertMate web UI |
| `http://127.0.0.1:8000/health` | CertMate health check |
| `http://127.0.0.1:8000/api/certificates` | Certificate management API |
| `http://127.0.0.1:8000/api/ca/root` | Download private CA root certificate |
| `http://127.0.0.1:20241/metrics` | cloudflared Prometheus metrics |
| `http://127.0.0.1:20241/ready` | cloudflared readiness probe |
