# platform/base

> 📚 System architecture, secrets-flow, and the tier-0 bootstrap order live in
> Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**.
> This README covers only this stack: what it is and how to deploy it.
> (Notion = prose/architecture; repo = compose/usage.)

The **unified per-host platform stack** — one compose project (`platform-base`)
that carries every tier-0 service and deploys in one of two **modes**, selected
by `COMPOSE_PROFILES`. It replaces the old separate `node/` and
`platform/{infisical,komodo}` stacks (folded into `services/` here).

## Services & modes

| Service (`services/`) | control-plane | node |
|---|:--:|:--:|
| databasus | ✓ | ✓ |
| zerobyte | ✓ | ✓ |
| infisical (+ db, redis) | ✓ | |
| infisical-agent | ✓ | ✓ |
| traefik | ✓ | ✓ |
| cloudflared | ✓ | ✓ |
| komodo-periphery | ✓ | ✓ |
| komodo (core + mongo) | ✓ | |

- **control-plane** — all services. Runs on the control-plane host only.
- **node** — the per-host edge (no Infisical, no Komodo Core). Runs everywhere else.

The active profile also picks the agent variant: `agent-control-plane` reaches
Infisical in-project at `http://infisical-app:8080`; `agent-node` uses the public
URL. What each host renders is set per host via `AGENT_SERVICES` (keys from
`services/infisical-agent/files/services.tab`).

Two extra profiles gate a **cold control-plane bootstrap** (cumulative subsets):

- **restore** — databasus + zerobyte only. Gate: optionally restore the Infisical
  DB volume before Infisical starts.
- **identity** — + Infisical. Gate: create the agent's machine identity in the
  fresh Infisical, if it doesn't already exist.

## Deploy

Per-host env (`AGENT_HOST`, `AGENT_SERVICES`, `COMPOSE_PROFILES`,
`INFISICAL_CLIENT_ID/SECRET`) is injected by **infra.ansible** (cold bootstrap)
and **Komodo** (steady state); `.env` holds local defaults. Secrets are never
committed.

Cold control-plane order (driven by infra.ansible, with a manual pause at each gate):

```
[restore?] docker compose --profile restore   up -d      # gate: restore Infisical DB
           docker compose --profile identity  up -d       # gate: create agent machine identity
           docker compose up -d agent-control-plane        # agent renders tier-0 /dev/shm/*.env
           docker compose --profile control-plane up -d    # bring up the rest
```

Node host: `up -d agent-node` (render) → `--profile node up -d`. The agent must
render `/dev/shm/*.env` before consumers are created (they read `${VAR:?err}` at
parse time); thereafter `/dev/shm` stays populated across redeploys.

Validate locally (Linux container — macOS has no `/dev/shm`):

```bash
docker run --rm -e COMPOSE_PROFILES=control-plane \
  -e AGENT_HOST=test -e AGENT_SERVICES=traefik \
  -e ZEROBYTE__BASE_URL=http://x:4096 -e DOCKER_VOLUMES=/srv -e ROOT_DOMAIN_NAME=homektb.com \
  -v "$PWD":/s -w /s docker:cli sh -c '
    printf "INFISICAL_ENCRYPTION_KEY=t\nINFISICAL_AUTH_SECRET=t\nINFISICAL_DB_PASSWORD=t\n" > /dev/shm/infisical-bootstrap.env
    printf "ZEROBYTE_APP_SECRET=t\n" > /dev/shm/node_zerobyte.env
    printf "CF_DNS_API_TOKEN=t\n" > /dev/shm/node_traefik.env
    docker compose config --services'
```
