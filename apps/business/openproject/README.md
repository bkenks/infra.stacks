# openproject

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[OpenProject](https://www.openproject.org/) — self-hosted project management. Reached at `openprj.ktbinternal.com`. Runs as several roles off one image (`web`, `worker`, `cron`, `seeder`) plus sidecars: `cache` (memcached), `hocuspocus` (collaborative editing), and `autoheal` (restarts unhealthy containers).

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

Exposed via this host's Traefik on the shared `proxy` network — no published host ports. Two routers, both on `openprj.ktbinternal.com`: `web` (`:8080`) is the catch-all that serves the app, and `hocuspocus` (`:1234`) is routed by `PathPrefix(/hocuspocus)` (prefix forwarded intact, higher priority than the catch-all) for the collaborative-editing websocket (`wss://openprj.ktbinternal.com/hocuspocus`). Wildcard `*.ktbinternal.com` TLS is issued per-host, so the routers just set `tls: true`.

`cron`/`seeder`/`web`/`worker` share a common base (image, `assets` volume, the `enterprise_token.rb` bind mount, restart policy) — merged into each service in `compose.stack.jsonnet` via a jsonnet `local opApp = {...}` object combined with `+`, instead of a YAML anchor.

`token/enterprise_token.rb` is a bind-mounted Ruby file (community enterprise-unlock patch) — bind-mounted at `/app/app/models/enterprise_token.rb` on all four app services. It is NOT generated/rendered; keep it as-is.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/openproject` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.openproject`):
  - `OPEN_PRJ_SECRET_KEY` — Rails `SECRET_KEY_BASE` (used by `cron`/`seeder`/`web`/`worker`).
  - `COLLAB_SERVER_SECRET` — shared secret between OpenProject and the hocuspocus collaborative-editing server. Rendered as `OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET` on the 4 app services AND as `SECRET` on `hocuspocus` itself.
- The agent renders them to `/dev/shm/openproject.env` on the **same host**; it also needs `/dev/shm/postgres.env` (`POSTGRES_USER`/`POSTGRES_PASS`) for the DB login. `compose.jsonnet`'s `include.env_file` pulls both in.

Non-secret config (host names, cache backend, thread counts, image versions, etc.) is baked directly into `compose.stack.jsonnet`'s `environment:` blocks — no `.env` file for it.

OpenProject connects to the shared Postgres on the external `shared-postgres` network (`postgres-db:5432`, database `openproject`). The old (pre-jsonnet) stack hardcoded the DB host as `postgres`, which was a latent bug — it's now `lib.compose.endpoint('postgres').private.host` (`postgres-db`), the correct shared-postgres address.

### Volume rename on first deploy

The old (pre-jsonnet) volume was the implicit `openproject_assets` (compose project name `openproject`, volume key `assets`). The jsonnet version names it explicitly `openproject-assets`. Before redeploying, migrate the data:

```bash
.scripts/rename-volume.sh openproject_assets openproject-assets
```

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
