# Infisical

Self-hosted Infisical: the secrets **store** (server) plus the **agent** that renders each
host's secrets to `/dev/shm/<stack>.env` (RAM, never disk). One stack directory, two Compose
profiles — the server runs on a single host, the agent runs on every host.

## Profiles

Nothing starts without a profile (see the interpolation note in `compose.jsonnet`):

| Host | `COMPOSE_PROFILES` | Runs |
|---|---|---|
| Infisical server host (littlebuddy) | `server,agent` | app + db + redis + agent |
| Every other host | `agent` | agent only |
| Ansible bootstrap | `server` | app + db + redis |

Compose interpolates the whole file on every host regardless of the active profile, so no
var uses `:?err` — an agent-only host has no server secrets and a bootstrap has no agent
creds, yet both are still interpolated. Every var carries an empty default; validation is at
runtime (the app rejects an empty `ENCRYPTION_KEY`; `entrypoint.sh` does `:?` checks).

Agent-only hosts have no `/dev/shm/platform.env`, and a missing `include: env_file:` is fatal,
so they set `ANSIBLE_SECRETS_FILE=/dev/null` (exists, empty); their machine-identity creds
come from Komodo's stack Environment.

## Agent: what it renders

A host declares services with one variable: `AGENT_SERVICES="postgres cloudflared komodo"`
(space/comma-separated). The catalogue is `registry.libsonnet` (`infisical.catalog`);
`templates/services.jsonnet` bakes one self-contained fragment per service into
`templates/<svc>.yaml` at build time. `entrypoint.sh` concatenates the named fragments under
`templates:` at startup — no runtime YAML parsing or template generation (the pre-commit hook
re-renders templates when `registry.libsonnet`/`templates/services.jsonnet` changes).

Registry entry `type`:

- `dump` (most services) — whole Infisical folder as `KEY=VALUE` (`listSecrets`).
- `map` — explicit `OUTPUT=FROM` renames via the entry's `keys` (`getSecretByName`), e.g.
  `cloudflared`'s `TUNNEL_TOKEN` → `CLOUDFLARE_TUNNEL_TOKEN`.
- `raw` — single secret's raw value, no `KEY=` prefix, via the entry's `key`.

`dest` MUST match what the consumer stack's `env_file` reads.

QUIRK: the Infisical template engine has no env access, so host-scoped paths (e.g.
cloudflared's `/hosts/<host>/cloudflared`) use a literal `${AGENT_HOST}` baked into the
fragment by jsonnet; `entrypoint.sh` substitutes it with the real host name (a single `sed`)
at concat time — the only substitution performed.

## Add a service to the agent

1. Add one entry to `infisical.catalog` in `lib/registry.libsonnet` (`project`, `folder`,
   `dest`, `type`; plus `keys` for `map` or `key` for `raw`).
2. `type=dump` if Infisical secret names already match the consumer's env vars, else `map`/`raw`.
3. Commit — pre-commit rebuilds `.deploy/`, including `templates/<svc>.yaml` (or `mise run render`).
4. Store the secrets in Infisical under the entry's folder; scope the host's machine identity
   to read it.
5. Append the service name to that host's `AGENT_SERVICES`.

## Deploy

Per-host runtime variables (Komodo per-server variables / Ansible):

```
COMPOSE_PROFILES=agent                  # or server,agent on the Infisical host
AGENT_HOST=<host>                       # selects ${AGENT_HOST} secret paths
AGENT_SERVICES="postgres cloudflared …"
INFISICAL_ADDRESS=<url>                 # public URL by default; the Infisical host overrides
INFISICAL_CLIENT_ID=… / INFISICAL_CLIENT_SECRET=…
ANSIBLE_SECRETS_FILE=/dev/null          # agent-only hosts; the server host points at platform.env
```

Each host gets its **own machine identity**, scoped to only the folders of its
`AGENT_SERVICES`. Creds are never committed — they come from Komodo per-server variables or
Ansible (`/dev/shm`) at runtime, and the secret file is wiped on read
(`remove_client_secret_on_read`).

## Health

`entrypoint.sh` stamps `/tmp/agent.last_err` with the epoch of every `ERR`/`FTL`/`PNC` log
line; the agent healthcheck marks the container unhealthy only while an error was logged
within the last 180s, auto-recovering once errors stop (no restart needed).
