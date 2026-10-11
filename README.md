# Portainer GitOps Infrastructure

This repository is the Git-backed source of truth for Docker stacks deployed through Portainer. It is being built for a Docker Desktop/WSL host and currently serves as an infrastructure design and configuration workspace; a complete automated GitOps pipeline is not checked in yet.

## What this will become

The intended operating model is:

1. A stack lives under `gitops/sources/<stack>/`.
2. Its Compose definition and documented environment are reviewed and committed to Git.
3. Portainer pulls the selected stack from Git and reconciles it on the Docker host.
4. Secrets are supplied through Portainer’s environment or secret-management features, never through committed files.
5. Named volumes preserve service state across container updates.

The primary target is the `ca-certmate-cloudflare-mesh` stack described in `.kiro/specs/ca-certmate-cloudflare-mesh/`. It will combine:

- **CertMate** — public Let’s Encrypt certificates for `rainbowsmokeofficial.com` and `mrrainbowsmoke.com` using Cloudflare DNS-01 challenges, plus a private CA for internal service names such as `host.docker.internal`.
- **cloudflared** — an outbound Cloudflare Tunnel connector that routes public hostnames to Docker services by container name.
- **`certmesh`** — a dedicated bridge network connecting the two services without exposing their management interfaces publicly.

The planned mesh keeps CertMate’s UI on `127.0.0.1:8000`, Cloudflare Tunnel metrics on `127.0.0.1:20241`, and persists CertMate data, certificates, logs, and backups in named volumes.

## Current state

The unified mesh has been specified but has not been implemented yet. The repository currently contains two standalone source stacks:

| Stack | Location | Current role |
| --- | --- | --- |
| CertMate | `gitops/sources/certmate/` | Certificate manager with persistent volumes and a loopback-only UI. |
| cloudflared | `gitops/sources/cloudflare/` | Outbound tunnel connector on the `cloudflared` Docker network. |

The migration to `gitops/sources/ca-certmate-cloudflare-mesh/` is tracked in `.kiro/specs/ca-certmate-cloudflare-mesh/tasks.md`. The unified Compose file, environment template, stack documentation, private-CA checks, and validation scripts are still outstanding.

## Repository layout

```text
.
├── .kiro/
│   ├── specs/       # Requirements, architecture, and implementation tasks
│   └── steering/    # Project-specific operating guidance
├── gitops/
│   ├── sources/     # Portainer stack definitions and environment files
│   ├── workflows/   # Planned operational workflows
│   ├── snippets/    # Reusable configuration fragments
│   └── scratchpad.md
└── README.md
```

`gitops/backups/` is intentionally ignored. Local Portainer backups can contain the Portainer database, certificates, and private keys; they must be protected like secrets and must not be published.

## Working with a stack

Each source stack is designed to be deployed from its own directory in Portainer. Review its `docker-compose.yml` and `stack.env` together, then provide required values in the Portainer stack environment before deploying. The Cloudflare tunnel’s public hostnames and origins are managed in Cloudflare Zero Trust because the connector uses a remotely managed tunnel.

For local validation, run Compose configuration checks only after supplying the required secrets through a secure environment source:

```powershell
docker compose -f gitops/sources/<stack>/docker-compose.yml config --quiet
```

Do not commit populated environment files. The Compose definitions use required-variable substitution for critical credentials so a deployment should fail before containers start when those values are missing.

## Security status

Before this repository is used as a shared or public Git remote:

- Rotate the non-empty credentials currently present in `gitops/sources/certmate/stack.env`.
- Remove those values from Git history and replace the file with a non-secret template.
- Add an explicit ignore rule or an approved secret-management workflow for populated `stack.env` files; the current `.gitignore` only covers `.env` and `gitops/backups/*`.
- Keep Portainer backup archives off Git and restrict access to the local backup directory.

This README documents the intended secret-handling model; it does not make the existing checked-in environment values safe.

## Planned next steps

1. Create `gitops/sources/ca-certmate-cloudflare-mesh/` with the unified Compose file and empty environment template.
2. Attach CertMate and cloudflared to the dedicated `certmesh` network and preserve CertMate’s named volumes.
3. Document the private-CA UI and API workflows and the Portainer deployment procedure.
4. Add checks for container hardening, volume declarations, required secrets, empty committed secret values, and DNS-01 timeout settings.
5. Validate the stack on the Docker host, then connect it to Portainer’s Git-based deployment flow.
