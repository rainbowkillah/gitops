# Requirements Document

## Introduction

This feature integrates CertMate and cloudflared into a unified certificate authority and tunnel mesh stack (`ca-certmate-cloudflare-mesh`). CertMate serves a dual role: it issues and automatically renews TLS certificates for the public domains `rainbowsmokeofficial.com` and `mrrainbowsmoke.com` via Cloudflare DNS-01 ACME challenges, and it operates as a private CA issuing certificates for internal mesh services (including `host.docker.internal`). A dedicated `certmesh` Docker bridge network connects CertMate and cloudflared so cloudflared can route public traffic to internal origins by container service name. All configuration is version-controlled in `gitops/sources/ca-certmate-cloudflare-mesh/` following the existing GitOps layout pattern and is manageable via Portainer Edge Agent without manual intervention.

---

## Glossary

- **CertMate**: The `fabriziosalmi/certmate` container responsible for ACME certificate issuance, renewal, and private CA operations.
- **cloudflared**: The `cloudflare/cloudflared` container that maintains outbound tunnel connections to the Cloudflare edge and routes public traffic to internal origins.
- **certmesh**: The dedicated Docker bridge network (`certmesh`) created by this stack that connects CertMate and cloudflared, enabling service-name-based routing between them.
- **DNS-01 Challenge**: An ACME challenge type where domain ownership is proven by creating a DNS TXT record via the Cloudflare API, used for issuing public certificates.
- **Private CA**: A self-signed certificate authority hosted within CertMate that issues certificates for internal services not reachable by a public ACME CA.
- **Public Domain**: One of `rainbowsmokeofficial.com` or `mrrainbowsmoke.com`, requiring a publicly trusted TLS certificate via Let's Encrypt.
- **Internal Service**: A container or host reachable only within the certmesh network, such as services on `host.docker.internal`, requiring a private CA certificate.
- **Portainer Edge Agent**: The Portainer component that applies GitOps stack definitions from version-controlled compose files to the Docker Desktop / WSL host.
- **Stack Folder**: The directory `gitops/sources/ca-certmate-cloudflare-mesh/` containing `docker-compose.yml`, `stack.env`, and `README.md` for this stack.
- **TUNNEL_TOKEN**: The Cloudflare Zero Trust tunnel token required by cloudflared to establish an authenticated outbound tunnel connection.
- **CLOUDFLARE_TOKEN**: The Cloudflare API token with DNS edit permissions required by CertMate to perform DNS-01 challenges.

---

## Requirements

### Requirement 1: GitOps Stack Layout

**User Story:** As a Portainer GitOps operator, I want the mesh stack defined in a dedicated folder following the established layout pattern, so that Portainer Edge Agent can deploy and update it without manual file management.

#### Acceptance Criteria

1. THE Stack Folder SHALL contain a `docker-compose.yml`, a `stack.env`, and a `README.md` at `gitops/sources/ca-certmate-cloudflare-mesh/`.
2. THE Stack Folder SHALL follow the same structural conventions as the existing `gitops/sources/cloudflare/` and `gitops/sources/certmate/` folders, including one compose file and one env file per stack.
3. WHEN Portainer Edge Agent applies the stack, THE `docker-compose.yml` SHALL be deployable without any manual file edits, provided `stack.env` contains all required secret values.
4. THE `stack.env` SHALL define every variable referenced in `docker-compose.yml` with a default value or an inline comment documenting the required value, except for secrets (`TUNNEL_TOKEN`, `CLOUDFLARE_TOKEN`, `API_BEARER_TOKEN`, `SECRET_KEY`, `CERTMATE_BACKUP_PASSPHRASE`) which SHALL have empty defaults and a comment directing the operator to supply them.
5. THE `README.md` SHALL document the deployment steps, required secrets, and network topology for the stack.

---

### Requirement 2: Dedicated certmesh Network

**User Story:** As a Docker operator, I want CertMate and cloudflared connected on a dedicated bridge network, so that cloudflared can reach CertMate-served origins by service name without sharing the existing `cloudflared` network.

#### Acceptance Criteria

1. THE `docker-compose.yml` SHALL define a Docker bridge network named `certmesh` with `driver: bridge` and `external: false`.
2. THE certmesh network SHALL be referenced by the variable `${CERTMESH_NETWORK_NAME:-certmesh}` so operators can override the name via `stack.env` without editing the compose file.
3. WHEN the stack is deployed, THE CertMate service SHALL be attached to the `certmesh` network.
4. WHEN the stack is deployed, THE cloudflared service SHALL be attached to the `certmesh` network.
5. THE `docker-compose.yml` SHALL NOT attach either service to the pre-existing `cloudflared` bridge network, keeping the two stacks network-isolated from each other.

---

### Requirement 3: CertMate Public Certificate Issuance via Cloudflare DNS-01

**User Story:** As a site owner, I want CertMate to automatically obtain and renew Let's Encrypt TLS certificates for `rainbowsmokeofficial.com` and `mrrainbowsmoke.com` via Cloudflare DNS-01, so that both public domains always have a valid, publicly trusted certificate without manual intervention.

#### Acceptance Criteria

1. WHEN the CertMate service starts, THE CertMate service SHALL be configured with `CLOUDFLARE_TOKEN` so it can perform Cloudflare DNS-01 challenges for `rainbowsmokeofficial.com` and `mrrainbowsmoke.com`.
2. WHEN a certificate for `rainbowsmokeofficial.com` or `mrrainbowsmoke.com` is within the renewal window (30 days before expiry by default), THE CertMate scheduler SHALL initiate a DNS-01 renewal challenge automatically without operator intervention.
3. WHEN a DNS-01 challenge is initiated, THE CertMate service SHALL create the required DNS TXT record via the Cloudflare API and remove it upon challenge completion.
4. THE CertMate service SHALL store issued certificates in the `certmate_certificates` named volume so certificates persist across container restarts and redeployments.
5. THE `stack.env` SHALL document `LETSENCRYPT_EMAIL` as a required value and SHALL include a placeholder that the operator replaces with a valid email address registered with the ACME CA.

---

### Requirement 4: CertMate Private CA for Internal Services

**User Story:** As a platform engineer, I want CertMate to act as a private CA for internal mesh services and `host.docker.internal`, so that internal services can use TLS without requiring public domain validation.

#### Acceptance Criteria

1. THE CertMate service SHALL expose its private CA functionality through the CertMate web UI so that an operator can issue internal certificates for `host.docker.internal` and other internal service names without using the API.
2. THE CertMate service SHALL expose its private CA functionality through the CertMate API so that automated tooling can issue internal certificates for `host.docker.internal` and other internal service names programmatically.
3. WHEN a certificate is requested for an internal service name (not a public ACME domain), THE CertMate service SHALL issue the certificate using its local private CA without contacting an external ACME endpoint.
4. THE CertMate service SHALL store private CA certificates and issued internal certificates in the `certmate_certificates` named volume.
5. THE `stack.env` SHALL include `CERTMATE_BACKUP_PASSPHRASE` so that encrypted backups of private CA material can be created and restored.

---

### Requirement 5: cloudflared Tunnel Integration

**User Story:** As a network operator, I want cloudflared to route public traffic to internal origins over the certmesh network, so that public hostnames defined in Cloudflare Zero Trust reach the correct internal containers.

#### Acceptance Criteria

1. WHEN the cloudflared service starts, THE cloudflared service SHALL authenticate using `TUNNEL_TOKEN` from the stack environment and establish an outbound connection to the Cloudflare edge.
2. WHILE the cloudflared service is connected, THE cloudflared service SHALL route requests to origins specified by their container service name and port on the `certmesh` network (e.g. `http://certmate:8000`).
3. THE cloudflared service SHALL expose a Prometheus metrics endpoint on `127.0.0.1:20241` on the host so that tunnel health can be monitored without exposing it to external networks.
4. THE `docker-compose.yml` SHALL configure a health check for the cloudflared service using the `/ready` endpoint on the metrics port, with an interval of 30 seconds, a timeout of 10 seconds, 3 retries, and a start period of 10 seconds.
5. THE cloudflared service SHALL run with `restart: unless-stopped` so that it recovers automatically from transient failures without operator intervention.
6. THE cloudflared service SHALL apply `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`, and `read_only: true` filesystem settings, consistent with the security baseline applied to all containers in this workspace.

---

### Requirement 6: CertMate Container Hardening

**User Story:** As a security-conscious operator, I want CertMate to run with the same hardened configuration as the existing stacks, so that the attack surface of the certificate authority is minimised.

#### Acceptance Criteria

1. THE CertMate service SHALL apply `cap_drop: [ALL]` and `security_opt: [no-new-privileges:true]` in the compose definition.
2. THE CertMate service SHALL bind its published port to `127.0.0.1` by default (`${CERTMATE_PORT_BIND:-127.0.0.1}:${CERTMATE_HOST_PORT:-8000}:${PORT:-8000}`) so the management UI is not exposed on external interfaces.
3. THE CertMate service SHALL configure log rotation using `driver: json-file` with `max-size: 10m` and `max-file: "3"` to prevent unbounded disk usage.
4. THE CertMate service SHALL define a health check using `curl -f http://localhost:${PORT:-8000}/health`, with an interval of 30 seconds, a timeout of 10 seconds, 3 retries, and a start period of 40 seconds.
5. THE CertMate service SHALL mount named volumes for `certmate_data`, `certmate_certificates`, `certmate_logs`, and `certmate_backups` so all persistent state survives container recreation.
6. THE CertMate service SHALL set `restart: unless-stopped` so it recovers automatically from transient failures.

---

### Requirement 7: Automated Renewal with Zero Manual Intervention

**User Story:** As an operator, I want certificate renewals to happen fully automatically, so that no manual steps are needed to keep certificates valid for public or internal services.

#### Acceptance Criteria

1. WHEN a certificate managed by CertMate is within the configured renewal window, THE CertMate scheduler SHALL initiate renewal automatically using the same issuance method (DNS-01 for public domains, private CA for internal) without operator intervention.
2. THE CertMate service SHALL persist its scheduler state in the `certmate_data` named volume so scheduled renewals survive container restarts.
3. IF a DNS-01 renewal attempt fails, THEN THE CertMate service SHALL log the failure with sufficient detail (domain name, error message, timestamp) to allow diagnosis without requiring live access to the container.
4. THE `stack.env` SHALL include `GUNICORN_TIMEOUT` set to a value of at least 300 seconds so that DNS-01 challenges on slow DNS propagation paths complete within the worker timeout.

---

### Requirement 8: Secret Management

**User Story:** As a GitOps operator, I want all secrets excluded from version-controlled files and supplied only through the Portainer stack environment, so that credentials are never committed to source control.

#### Acceptance Criteria

1. THE `stack.env` committed to source control SHALL contain empty values for `TUNNEL_TOKEN`, `CLOUDFLARE_TOKEN`, `API_BEARER_TOKEN`, `SECRET_KEY`, and `CERTMATE_BACKUP_PASSPHRASE`, each accompanied by a comment directing the operator to supply the value via the Portainer stack environment UI.
2. THE `docker-compose.yml` SHALL reference `TUNNEL_TOKEN` with a required substitution (`${TUNNEL_TOKEN:?...}`) that causes stack deployment to fail with a descriptive error message if the variable is not set.
3. THE `docker-compose.yml` SHALL reference `CLOUDFLARE_TOKEN` such that CertMate refuses to start DNS-01 challenges if the token is absent or invalid.
4. THE `.gitignore` at the repository root SHALL exclude any file named `*.env` that contains populated secret values, and the committed `stack.env` SHALL serve only as a documented template.
