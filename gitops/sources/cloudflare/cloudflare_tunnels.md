# Cloudflare Tunnel in Portainer

Deploy `cloudflared.compose.yml` as a Portainer stack. In the stack's environment
variables, add `TUNNEL_TOKEN` and paste a current tunnel token from Cloudflare.
Do not put the token in this file or commit it to source control.

The tunnel routes are remotely managed, so configure public hostnames and origin
services in Cloudflare Zero Trust: **Networking > Tunnels > your tunnel**.

If the origin is another container, connect both containers to the same Docker
network and use that container's service name and port as the origin address.
For example: `http://my-app:8080`.

This stack publishes no ports; `cloudflared` makes only outbound connections to
Cloudflare. For high availability, deploy another copy of this same stack on a
different Docker host with the same token.
