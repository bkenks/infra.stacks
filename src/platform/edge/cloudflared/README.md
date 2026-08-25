# cloudflared
Per-host Cloudflare Tunnel connector — joins the host's local `proxy` bridge network and routes public ingress to that host's Traefik (`https://traefik:443`). Per-host because `proxy` is a per-host bridge and each host's Traefik only knows its own containers.

## Deploy
- Secrets: Infisical per-host folder `/hosts/<host>/cloudflared` supplies `TUNNEL_TOKEN` through the infisical-secrets provider. The deploy environment has to set `AGENT_HOST`; compose interpolates it into the provider's path.
- QUIRK: one tunnel/token per host — Cloudflare round-robins replicas of the same tunnel, which would send a host's hostnames to the wrong connector.
