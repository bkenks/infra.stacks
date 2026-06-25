# platform/base

> 📚 System architecture, secrets-flow, and the tier-0 bootstrap order live in
> Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**.
> This README covers only this stack: what it is and how to deploy it.
> (Notion = prose/architecture; repo = compose/usage.)

The per-host **platform services** — the tier-0 stacks that underpin every host.
Each one under `services/<svc>/` is a **self-contained, independently deployable
compose project** (its own `name:`, its own internal network, joining the shared
external nets for anything cross-service). They are **loosely coupled**: no
shared compose project, no profiles, no modes — deploy, redeploy, or restart any
one on its own without touching the others.

The top-level `compose.yaml` is just a **convenience launcher** that `include:`s
them all, so a single `docker compose up` here brings the whole platform up
together (as one fused `platform-base` project) for local/dev. It carries no
modes and no gates.

## Services

| Service (`services/`) | what it is | net |
|---|---|---|
| traefik | per-host reverse proxy (owns the shared `proxy` net) | proxy |
| infisical (+ db, redis) | secrets manager (control-plane host only) | infisical, proxy |
| infisical-agent | renders each host's secrets to `/dev/shm/*.env` | proxy |
| komodo (core + mongo) | orchestrator UI + DB (control-plane host only) | komodo, proxy |
| komodo-periphery | per-host Komodo agent | (docker socket) |
| cloudflared | Cloudflare Tunnel ingress | proxy |
| databasus | DB backup agent | db-backups |
| zerobyte | volume backup agent | (host/Tailscale) |

**Which services run on a host** is a deploy-time choice (which stacks you point
at the host), not a compose mode. The Infisical host runs everything; every other
host runs only the edge set (traefik, infisical-agent, komodo-periphery,
cloudflared, databasus, zerobyte).

The Infisical agent reaches Infisical via `INFISICAL_ADDRESS` (public URL by
default; the Infisical host overrides it to the internal `http://infisical-app:8080`).
What each host renders is set per host via `AGENT_SERVICES` (keys from
`services/infisical-agent/files/services.tab`).

## Deploy

Per-host env (`AGENT_HOST`, `AGENT_SERVICES`, `INFISICAL_ADDRESS`,
`INFISICAL_CLIENT_ID/SECRET`) is injected by **infra.ansible** (cold bootstrap)
and **Komodo** (steady state); `.env` holds local defaults. Secrets are never
committed.

Deploy a single service:

```bash
docker compose -f services/traefik/compose.yaml up -d
```

**Bootstrap ordering** still matters but lives in the deploy layer (infra.ansible /
a Komodo procedure), not in compose. The Infisical agent must render the tier-0
`/dev/shm/*.env` files *before* the services that read `${VAR:?err}` at parse time,
and traefik must create the shared `proxy` net first. So a cold control-plane
comes up roughly: traefik → infisical → (create agent machine identity) →
infisical-agent (renders `/dev/shm`) → the rest. Thereafter `/dev/shm` stays
populated across redeploys.

Validate the compose locally (Linux container — macOS has no `/dev/shm`):

```bash
docker run --rm -e AGENT_HOST=test -e AGENT_SERVICES=traefik \
  -e ZEROBYTE__BASE_URL=http://x:4096 -e DOCKER_VOLUMES=/srv -e ROOT_DOMAIN_NAME=homektb.com \
  -v "$PWD":/s -w /s docker:cli sh -c '
    printf "INFISICAL_ENCRYPTION_KEY=t\nINFISICAL_AUTH_SECRET=t\nINFISICAL_DB_PASSWORD=t\n" > /dev/shm/infisical-bootstrap.env
    printf "ZEROBYTE_APP_SECRET=t\n" > /dev/shm/node_zerobyte.env
    printf "CF_DNS_API_TOKEN=t\n" > /dev/shm/node_traefik.env
    printf "CLOUDFLARE_TUNNEL_TOKEN=t\n" > /dev/shm/node_cloudflared.env
    docker compose config --services'
```
