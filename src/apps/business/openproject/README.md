# openproject

[OpenProject](https://www.openproject.org/) — self-hosted project management. Reached at `openprj.ktbinternal.com` via Traefik. Runs `web`/`worker`/`cron`/`seeder` off one image plus `cache` (memcached), `hocuspocus` (collaborative editing), and `autoheal`.

Source of truth: `compose.jsonnet` — don't edit the generated YAML (renders both `compose.yaml` and `compose.stack.yaml`).

## Deploy

Deployed via Komodo. Infisical `/openproject` (`OPEN_PRJ_SECRET_KEY`, `COLLAB_SERVER_SECRET`) → `/dev/shm/openproject.env`; also needs `/dev/shm/postgres.env` (shared Postgres, `postgres-db:5432`, db `openproject`). `COLLAB_SERVER_SECRET` renders as `OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET` on the app services and as `SECRET` on `hocuspocus`.

`hocuspocus` is routed via `PathPrefix(/hocuspocus)` at higher priority than `web`'s catch-all — needed for `wss://openprj.ktbinternal.com/hocuspocus`.

`token/enterprise_token.rb` is a bind-mounted community enterprise-unlock patch — not generated, keep as-is.

First deploy: rename volume `openproject_assets` → `openproject-assets`:
```bash
.scripts/rename-volume.sh openproject_assets openproject-assets
```
