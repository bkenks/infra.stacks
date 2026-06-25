# platform

> 📚 System architecture, secrets-flow, and the tier-0 bootstrap order live in
> Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**.
> This README covers only this stack: what it is and how to deploy it.
> (Notion = prose/architecture; repo = compose/usage.)

The per-host **platform services** — the tier-0 stacks that underpin every host —
organised into **three independently-deployable levels**:

| Level | File | Project | Use |
|---|---|---|---|
| **service** | `<group>/<svc>/compose.yaml` | the service | deploy/redeploy one service |
| **group** | `<group>/compose.yaml` | the group | deploy a functional unit |
| **purpose** | `./compose.yaml` | `platform` | the whole platform; selects by service / group / phase |

Loosely coupled: service and group composes carry **no profiles** and deploy
standalone with no flags. Inter-service traffic rides the shared external nets
(`proxy`, `db-backups`); each multi-container service keeps its own internal net.
Every container is aliased on each network by its `SERVICE_NAME` (set in the
service's interpolation env), so services address each other by a definitive,
project-independent name rather than the compose key / project-prefixed default.

## Groups

| Group (phase) | Services | What |
|---|---|---|
| **backup-manager** (1) | databasus, zerobyte | DB + volume backups |
| **secrets-manager** (2) | infisical (+db/redis), infisical-agent | secrets + renderer |
| **edge** (3) | traefik, cloudflared | reverse proxy + tunnel ingress |
| **container-manager** (4) | komodo (core+mongo), komodo-periphery | orchestrator |

**Which services run on a host** is a deploy choice, not a compose mode. The
control-plane host runs all four groups; every other host runs only the edge +
backup groups plus the `infisical-agent` and `komodo-periphery` services (Infisical
and Komodo Core live on the control plane).

## Deploy

**One service** — from its own dir (or `project_src=<dir>`):

```bash
cd edge/traefik && docker compose up -d
```

**One group** — from the group dir (Komodo/Ansible use `project_src=<group dir>`):

```bash
cd backup-manager && docker compose up -d
```

> Run a group from its OWN dir (not `-f backup-manager/compose.yaml` from here) —
> a service's interpolation `env_file` only resolves with the group dir as the
> project root.

**The platform entrypoint** (`./compose.yaml`, project `platform`) — one file, many
options. Each service carries `[phaseN, <group>, <service>]` profile tags and
`COMPOSE_PROFILES` matches ANY of them, so the same entrypoint selects at three grains:

```bash
COMPOSE_PROFILES=traefik docker compose up -d   # one SERVICE
COMPOSE_PROFILES=edge    docker compose up -d   # one GROUP (traefik + cloudflared)
COMPOSE_PROFILES=phase1  docker compose up -d   # one PHASE (== backup-manager)
```

`docker compose up` is **additive** (a later phase never stops an earlier one), so the
gated cold bootstrap is just sequential phase ups, by hand or via Ansible:

```bash
COMPOSE_PROFILES=phase1 docker compose up -d   # backup-manager
COMPOSE_PROFILES=phase2 docker compose up -d   # + secrets-manager (phase1 stays up)
COMPOSE_PROFILES=phase3 docker compose up -d   # + edge
COMPOSE_PROFILES=phase4 docker compose up -d   # + container-manager
```

One-shot everything: `COMPOSE_PROFILES=phase1,phase2,phase3,phase4`. Profiles live ONLY
in this top `compose.yaml`, so the group/service composes stay clean and standalone.

### Gates (operator pauses BETWEEN phases)

```
phase1  ──[restore gate: restore the Infisical DB volume]──▶ phase2
phase2  ──[identity gate: create the agent machine-identity;
           the agent then renders /dev/shm/*.env — wait for them]──▶ phase3 ──▶ phase4
```

The agent reaches Infisical via `INFISICAL_ADDRESS` (public URL default; the
Infisical host overrides to internal `http://infisical-app:8080`). What each host
renders is set per host via `AGENT_SERVICES` (keys from
`secrets-manager/infisical-agent/files/services.tab`). The agent retries auth, so
it tolerates coming up in phase 2 before the identity exists — it renders once the
identity is created.

## Deploy vars

Per-host env is injected by **infra.ansible** (cold bootstrap) and **Komodo**
(steady state); `.env` holds local defaults. Secrets are never committed. Each
group's entrance compose lists its required deploy vars; the standard set threaded
through the services is `ROOT_DOMAIN_NAME`, `HOST_IP` / `TAILSCALE_IP` /
`TAILSCALE_HOSTNAME`, `DOCKER_VOLUMES`, `AGENT_HOST` / `AGENT_SERVICES`.

Validate the compose locally (Linux container — macOS has no `/dev/shm`):

```bash
docker run --rm -e COMPOSE_PROFILES=phase4 -e AGENT_HOST=test -e AGENT_SERVICES=traefik \
  -e ZEROBYTE__BASE_URL=http://x:4096 -e DOCKER_VOLUMES=/srv -e ROOT_DOMAIN_NAME=homektb.com \
  -v "$PWD":/s -w /s docker:cli sh -c '
    printf "INFISICAL_ENCRYPTION_KEY=t\nINFISICAL_AUTH_SECRET=t\nINFISICAL_DB_PASSWORD=t\n" > /dev/shm/infisical-bootstrap.env
    printf "ZEROBYTE_APP_SECRET=t\n" > /dev/shm/node_zerobyte.env
    printf "CF_DNS_API_TOKEN=t\n" > /dev/shm/node_traefik.env
    printf "CLOUDFLARE_TUNNEL_TOKEN=t\n" > /dev/shm/node_cloudflared.env
    docker compose config --services'
```
