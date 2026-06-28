# infisical-agent

> 📚 System architecture, secrets-flow, and the tier-0 bootstrap order live in Notion →
> **Architecture — How It All Connects** / **Bootstrapping a Host from Scratch**.
> This file covers only `node/infisical-agent`: what it does, how to deploy/use it,
> and its quirks. (Notion = prose/architecture; repo = compose/usage.)

Renders a host's stack secrets from Infisical to `/dev/shm/<stack>.env` (RAM, never disk). Each consumer stack pulls its file in via the compose `include: -> env_file:` convention. Long-running on **every** host while the Infisical server runs on only one.

## How it reaches Infisical — `INFISICAL_ADDRESS`

The agent is the same everywhere — one service, no compose profiles. The only
per-host difference is the `INFISICAL_ADDRESS` env var. The agent **always** joins
the `proxy` network (harmless on a plain node; required on the Infisical host so
it can reach the app directly before Traefik / the public URL exist).

| Host | `INFISICAL_ADDRESS` | For |
|---|---|---|
| the Infisical host | `http://infisical-app:8080` (internal) | runs Infisical itself; can bootstrap before Traefik exists |
| every other host | `https://infisical.homektb.com` (public) — the default | reaches Infisical over the public URL |

`.env` defaults `INFISICAL_ADDRESS` to the public URL; the Infisical host overrides it.

## What it renders — `AGENT_SERVICES` + the registry

There are **no per-host config files**. A host declares what to render with one variable:

```
AGENT_SERVICES="postgres traefik cloudflared komodo"   # space- or comma-separated
```

The catalogue lives in **`registry.libsonnet`** (`agentServices`). `services.jsonnet`
generates **one self-contained agent-config fragment per service** into
**`templates/<svc>.yaml`** — each a single `templates:` list entry with the Go
template **inline** (`template-content`). At startup `entrypoint.sh` writes the
static `infisical:`/`auth:` header, then for each name in `AGENT_SERVICES` simply
**concatenates** that service's fragment under a `templates:` key. It does **no**
YAML parsing and **no** template generation — all of that is baked at build time
by jsonnet. The fragments are committed; the pre-commit hook re-renders them
whenever `registry.libsonnet`/`services.jsonnet` changes (`.jsonnet/render.sh`).

Each registry entry has a `type` that decides the inline template `services.jsonnet` bakes:

- **`type=dump`** (most services) — renders the **entire Infisical folder** as `KEY=VALUE` via `listSecrets`. Works because the secret names already equal the consumer's env-var names.
- **`type=map`** — explicit `OUTPUT=FROM` renames/duplications via the entry's `keys` map (`getSecretByName`). E.g. `komodo` renames `KOMODO_DB_*` → `KOMODO_DATABASE_*` and reuses the DB creds for `MONGO_INITDB_ROOT_*`; `cloudflared` renames `TUNNEL_TOKEN` → `CLOUDFLARE_TUNNEL_TOKEN`.
- **`type=raw`** — a single secret's raw value, no `KEY=` prefix, via the entry's `key` (for non-`KEY=VALUE` files, e.g. `databasus`'s `.key` bind mount).

`dest` MUST match what the consumer stack's compose reads via `env_file` — don't rename it without updating the consumer.

### `${AGENT_HOST}` substitution

The Infisical template engine has no env access, so host-specific secret paths (cloudflared's `/hosts/<host>/cloudflared`) can't be expressed in the template directly. The literal `${AGENT_HOST}` is baked into the fragment by jsonnet, and `entrypoint.sh` substitutes it with the real host name (a single `sed`) as it concatenates the fragment — the only substitution performed; secret *values* are still fetched by the agent at render time.

## Add a service

1. Add **one entry** to `agentServices` in `.jsonnet/lib/registry.libsonnet` (`project`, `folder`, `dest`, `type`; plus `keys` for `map` or `key` for `raw`).
2. If the Infisical secret names already match the consumer's env vars → `type=dump`. Otherwise use `type=map` (renames) or `type=raw` (single raw value).
3. Commit — the pre-commit hook re-renders `templates/<svc>.yaml` (or run `.jsonnet/render.sh platform/secrets-manager/infisical-agent/services.jsonnet`).
4. Store the secrets in Infisical under the entry's `folder`; scope each consuming host's machine identity to read it.
5. Append the service name to that host's `AGENT_SERVICES`.

## Deploy

Per-host runtime variables (Komodo per-server variables / Ansible):

```
AGENT_HOST=<host>                       # selects ${AGENT_HOST} secret paths
AGENT_SERVICES="postgres traefik …"     # which services to render
INFISICAL_ADDRESS=<url>                  # override only on the Infisical host (internal addr)
INFISICAL_CLIENT_ID=… / INFISICAL_CLIENT_SECRET=…   # machine-identity creds
```

```bash
# most hosts — via Komodo, with the vars above (INFISICAL_ADDRESS defaults to the public URL).
# the Infisical host — via Ansible at bootstrap (pre-writes /dev/shm creds), INFISICAL_ADDRESS=http://infisical-app:8080.
```

Each host gets its **own machine identity**, scoped in Infisical to only the folders of the services in its `AGENT_SERVICES`. Machine-identity creds are never committed — they come from Komodo per-server variables (`INFISICAL_CLIENT_ID/SECRET`, env) or Ansible (`/dev/shm`) at runtime, and the secret file is wiped on read (`remove_client_secret_on_read`).

## Health

The agent stays running even when a template/auth permanently fails, so liveness never flips it. `entrypoint.sh` stamps `/tmp/agent.last_err` with the epoch of every `ERR`/`FTL`/`PNC` log line; the healthcheck (in `compose/agent.yml`) marks the container unhealthy only while an error was logged within the last 180s — a still-broken agent re-logs within the window and stays unhealthy, and once errors stop the stamp ages out and it recovers on its own with no restart.
