## Stack: openproject

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[OpenProject](https://www.openproject.org/) — self-hosted project management. Reached at `openprj.homektb.com`. Runs as several roles off one image (`web`, `worker`, `cron`, `seeder`) plus sidecars: `cache` (memcached), `hocuspocus` (collaborative editing), and `autoheal` (restarts unhealthy containers). `web` publishes `8080` and `hocuspocus` publishes `1234`.

### Where each value goes

- **Literal, non-secret, injected into a container** → `container-envs/<name>.env`
- **Anything with `${...}` (secrets, cross-service refs)** → `yamls/secrets.yaml`
- **Interpolation-only vars (names, version tags)** →
  `interpolation-envs/main.env`

This split exists because a service's `env_file:` is **not** interpolated, so
`${...}` only resolves in the compose body — see the header in
`yamls/secrets.yaml`.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host
and this stack pulls them in — how that works → Notion: [Bootstrapping a Host
from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd)
(the Infisical agent secrets-flow).

This stack's specifics:
- App secrets live in Infisical under the `/openproject` folder; add a template
  entry in the agent config (`node/infisical-agent`) that renders them to
  `/dev/shm/openproject.env`:
  - `OPEN_PRJ_SECRET_KEY` — Rails `SECRET_KEY_BASE`.
  - `COLLAB_SERVER_SECRET` — shared secret between OpenProject and the hocuspocus
    collaborative-editing server.
- Postgres login (`POSTGRES_USER`, `POSTGRES_PASS`) comes from the shared
  `/postgres` folder, rendered to `/dev/shm/postgres.env` (same file the other
  stacks on the shared Postgres use).
- `compose.yaml`'s `include: -> env_file:` pulls both `/dev/shm` files in.

OpenProject connects to the shared Postgres on the external `postgres_shared`
network at `postgres-shared:5432`, database `openproject`.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed.)
