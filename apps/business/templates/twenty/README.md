# twenty

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Twenty](https://twenty.com/) — open-source CRM. Reached at `twenty.ktbinternal.com` via Traefik, forwarding to the `server` container's port `3000`. Ships with a dedicated `redis` (cache/queue) and a `worker` sidecar that runs the same image as `server` but processes background jobs instead of serving HTTP.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Services

- **redis** (`redis:8.6.1`) — cache/queue broker. Internal only, no Traefik, no shared-postgres join.
- **server** (`twentycrm/twenty:v1.18.1`) — the Twenty web/API. Only service exposed to Traefik. Joins `shared-postgres` to reach the DB.
- **worker** (`twentycrm/twenty:v1.18.1`, `command: yarn worker:prod`) — background job processor, same image and env as `server`, plus `DISABLE_DB_MIGRATIONS=true` and `DISABLE_CRON_JOBS_REGISTRATION=true` (migrations/cron registration already run on `server`; running them again here would race). Not exposed to Traefik.

The old dedicated `twenty` Docker network (redis↔server↔worker) is dropped — all three now share the standard per-stack default network the jsonnet convention generates.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/twenty` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.twenty`):
  - `TWENTY_SECRET` — mapped to the in-container `APP_SECRET`.
  - `TWENTY_GOOGLE_CLIENT_ID` — mapped to `AUTH_GOOGLE_CLIENT_ID`.
  - `TWENTY_GOOGLE_CLIENT_SECRET` — mapped to `AUTH_GOOGLE_CLIENT_SECRET`.
- The agent renders them to `/dev/shm/twenty.env` on the same host; it also needs `/dev/shm/postgres.env` (`POSTGRES_USER`/`POSTGRES_PASS`) for the DB login. `compose.jsonnet`'s `include.env_file` pulls both in. Both `server` and `worker` interpolate all three plus the Postgres creds — they run the same image against the same DB/secrets.

Non-secret config (ports, hostnames, Redis/Postgres wiring, Google callback URLs) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

### Bug fixes vs. the old (pre-jsonnet) config

- The old `networks: { postgres: { name: shared-postgres } }` was missing `external: true` — `lib.compose.join('postgres')` sets this correctly now.
- The old `POSTGRES_HOST_CONTAINER=postgres` pointed at a container alias that doesn't match the shared-postgres owner's real name. Now derived from the registry: `lib.compose.endpoint('postgres').private.host` → `postgres-db`.

### Traefik

Previously published directly on host port `3030:3000` with no Traefik integration. This migration adds Traefik on `server` only (`worker` has no exposed port and no Traefik labels): `expose: 3000`, reachable via `https://twenty.ktbinternal.com`.

### Volume rename on first deploy

The old (pre-jsonnet) volume was implicit, under the old Compose project name `twenty-production` → `twenty-production_server-storage`. The jsonnet version names it explicitly `twenty-server-storage`, shared by both `server` and `worker`. Before redeploying, migrate the data:

```bash
.scripts/rename-volume.sh twenty-production_server-storage twenty-server-storage
```

### Staging dropped

The old `compose.staging.yaml` + staging env are dropped in this migration — this stack now converts **production only**. The vendored upstream `.env.example` is also removed — no longer needed once config is baked into jsonnet.

### Compose Commands

*Validate the merged config locally (no deploy host needed):*
```bash
tests/render_compose.sh            # render + validate the merged config
tests/render_compose.sh --services # any `docker compose config` flag passes through
```

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
