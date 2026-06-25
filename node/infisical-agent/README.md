# infisical-agent

> 📚 System architecture, secrets-flow, and the tier-0 bootstrap order live in Notion →
> **Architecture — How It All Connects** / **Bootstrapping a Host from Scratch**.
> This file covers only `node/infisical-agent`: what it does, how to deploy/use it,
> and its quirks. (Notion = prose/architecture; repo = compose/usage.)

Renders a host's stack secrets from Infisical to `/dev/shm/<stack>.env` (RAM, never disk). Each consumer stack pulls its file in via the compose `include: -> env_file:` convention. Long-running on **every** host while the Infisical server runs on only one.

## Two modes (compose profile)

The agent is the same everywhere; the only per-mode difference is how it reaches Infisical (and, for the control plane, joining the `proxy` network so it can reach the app before Traefik / the public URL exist):

| Profile | Infisical address | Network | For |
|---|---|---|---|
| `control-plane` | `http://infisical-app:8080` (internal) | joins `proxy` | the host that runs Infisical itself; can bootstrap before Traefik exists |
| `node` | `https://infisical.homektb.com` (public) | default | every other host |

Set the profile via `COMPOSE_PROFILES` (`.env` defaults it to `node`).

## What it renders — `AGENT_SERVICES` + the registry

There are **no per-host config files**. A host declares what to render with one variable:

```
AGENT_SERVICES="postgres traefik cloudflared komodo"   # space- or comma-separated
```

`entrypoint.sh` reads each name from the **service registry** (`files/services.tab`) and **generates** the agent config at startup. The registry is the global catalogue — one pipe-delimited row per service:

```
service | project | env | folder | dest | type
```

- **`type=dump`** (the default, 15 of 18 services) — renders the **entire Infisical folder** as `KEY=VALUE` via `listSecrets`. Works because the secret names already equal the consumer's env-var names. No template file needed; it's generated on the fly.
- **`type=custom`** — uses the hand-written `files/configs/templates/<service>.tpl` verbatim. Only for the cases a folder dump can't express:
  - `komodo` — renames `KOMODO_DB_*` → `KOMODO_DATABASE_*` and reuses the DB creds for `MONGO_INITDB_ROOT_*`
  - `databasus` — renders a raw value to a `.key` file (not `KEY=VALUE`)
  - `cloudflared` — host-scoped folder `/hosts/<host>/cloudflared` + renames `TUNNEL_TOKEN` → `CLOUDFLARE_TUNNEL_TOKEN`

`dest` MUST match what the consumer stack's compose reads via `env_file` — don't rename it without updating the consumer.

### `${AGENT_HOST}` substitution

The Infisical template engine has no env access, so host-specific secret paths (cloudflared's `/hosts/<host>/cloudflared`) can't be expressed in a template or registry folder directly. `entrypoint.sh` substitutes the literal `${AGENT_HOST}` (in both the registry `folder` and any custom `.tpl`) with the real host name before the agent runs — the only substitution performed; secret *values* are still fetched by the agent at render time.

## Add a service

1. Add **one row** to `files/services.tab` (`service | project | env | folder | dest | type`).
2. If the Infisical secret names already match the consumer's env vars → `type=dump`, done. Otherwise add `files/configs/templates/<service>.tpl` and set `type=custom`.
3. Store the secrets in Infisical under the row's `folder`; scope each consuming host's machine identity to read it.
4. Append the service name to that host's `AGENT_SERVICES`.

## Deploy

Per-host runtime variables (Komodo per-server variables / Ansible):

```
AGENT_HOST=<host>                       # selects ${AGENT_HOST} secret paths
AGENT_SERVICES="postgres traefik …"     # which services to render
INFISICAL_CLIENT_ID=… / INFISICAL_CLIENT_SECRET=…   # machine-identity creds (node path)
```

```bash
# node (most hosts) — via Komodo, with COMPOSE_PROFILES=node and the vars above.
# control-plane — via Ansible at bootstrap (pre-writes /dev/shm creds), COMPOSE_PROFILES=control-plane.
```

Each host gets its **own machine identity**, scoped in Infisical to only the folders of the services in its `AGENT_SERVICES`. Machine-identity creds are never committed — they come from Komodo per-server variables (`INFISICAL_CLIENT_ID/SECRET`, env) or Ansible (`/dev/shm`) at runtime, and the secret file is wiped on read (`remove_client_secret_on_read`).

## Health

The agent stays running even when a template/auth permanently fails, so liveness never flips it. `entrypoint.sh` stamps `/tmp/agent.last_err` with the epoch of every `ERR`/`FTL`/`PNC` log line; the healthcheck (in `compose/agent.yml`) marks the container unhealthy only while an error was logged within the last 180s — a still-broken agent re-logs within the window and stays unhealthy, and once errors stop the stamp ages out and it recovers on its own with no restart.
