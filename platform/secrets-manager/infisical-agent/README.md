# infisical-agent
Renders a host's stack secrets from Infisical to `/dev/shm/<stack>.env` (RAM, never disk); each consumer stack pulls its file in via the compose `include: -> env_file:` convention. Long-running on **every** host.

## How it reaches Infisical

One service, no profiles — the only per-host difference is `INFISICAL_ADDRESS`. The Infisical host itself uses `http://infisical-app:8080` (bootstraps before Traefik exists); every other host uses the public `https://infisical.ktbinternal.com` (the `.env` default). The agent always joins the `proxy` network.

## What it renders

A host declares services with one variable: `AGENT_SERVICES="postgres cloudflare__dns-api-token cloudflared komodo"` (space/comma-separated). The catalogue is `registry.libsonnet` (`agentServices`); `services.jsonnet` bakes one self-contained fragment per service into `templates/<svc>.yaml` at build time. `entrypoint.sh` just concatenates the named fragments under `templates:` at startup — no runtime YAML parsing or template generation (pre-commit hook re-renders templates when `registry.libsonnet`/`services.jsonnet` changes).

Registry entry `type`:

- `dump` (most services) — whole Infisical folder as `KEY=VALUE` (`listSecrets`).
- `map` — explicit `OUTPUT=FROM` renames via the entry's `keys` (`getSecretByName`), e.g. `cloudflared`'s `TUNNEL_TOKEN` → `CLOUDFLARE_TUNNEL_TOKEN`.
- `raw` — single secret's raw value, no `KEY=` prefix, via the entry's `key` (e.g. `databasus`'s `.key` mount).

`dest` MUST match what the consumer stack's `env_file` reads.

QUIRK: the Infisical template engine has no env access, so host-scoped paths (e.g. cloudflared's `/hosts/<host>/cloudflared`) use a literal `${AGENT_HOST}` baked into the fragment by jsonnet; `entrypoint.sh` substitutes it with the real host name (a single `sed`) at concat time — the only substitution performed.

## Add a service

1. Add one entry to `agentServices` in `.jsonnet/lib/registry.libsonnet` (`project`, `folder`, `dest`, `type`; plus `keys` for `map` or `key` for `raw`).
2. `type=dump` if Infisical secret names already match the consumer's env vars, else `map` or `raw`.
3. Commit — pre-commit re-renders `templates/<svc>.yaml` (or run `.jsonnet/render.py platform/secrets-manager/infisical-agent/services.jsonnet`).
4. Store the secrets in Infisical under the entry's folder; scope the consuming host's machine identity to read it.
5. Append the service name to that host's `AGENT_SERVICES`.

## Deploy

Per-host runtime variables (Komodo per-server variables / Ansible):

```
AGENT_HOST=<host>                       # selects ${AGENT_HOST} secret paths
AGENT_SERVICES="postgres cloudflare__dns-api-token …"
INFISICAL_ADDRESS=<url>                 # override only on the Infisical host
INFISICAL_CLIENT_ID=… / INFISICAL_CLIENT_SECRET=…
```

Each host gets its **own machine identity**, scoped to only the folders of its `AGENT_SERVICES`. Creds are never committed — they come from Komodo per-server variables or Ansible (`/dev/shm`) at runtime, and the secret file is wiped on read (`remove_client_secret_on_read`).

## Health

`entrypoint.sh` stamps `/tmp/agent.last_err` with the epoch of every `ERR`/`FTL`/`PNC` log line; the healthcheck marks the container unhealthy only while an error was logged within the last 180s, auto-recovering once errors stop (no restart needed).
