# cloudflared
Per-host Cloudflare Tunnel connector — joins the host's local `proxy` bridge network and routes public ingress to that host's Traefik (`https://traefik:443`). Per-host because `proxy` is a per-host bridge and each host's Traefik only knows its own containers.

## Deploy
- Secrets: Infisical (per-host folder `/hosts/<host>/cloudflared`) `CLOUDFLARE_TUNNEL_TOKEN` → `/dev/shm/cloudflared-bootstrap.env`.
- QUIRK: one tunnel/token per host — Cloudflare round-robins replicas of the same tunnel, which would send a host's hostnames to the wrong connector.
