# openproject

[OpenProject](https://www.openproject.org/) — self-hosted project management. Reached at `openprj.ktbinternal.com` via Traefik. Runs `web`/`worker`/`cron`/`seeder` off one image plus `cache` (memcached), `hocuspocus` (collaborative editing), and `autoheal`.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Secrets come from Infisical `/openproject` through the infisical-secrets provider, injected under the names the containers read: `SECRET_KEY_BASE`, `DATABASE_URL`, `OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET` (the Rails services) and `SECRET` (hocuspocus). The last two hold the same value, so the bundle carries it twice — the provider injects values, it does not rename them. `DATABASE_URL` is stored whole (shared Postgres, `postgres-db:5432`, db `openproject`).

`hocuspocus` is routed via `PathPrefix(/hocuspocus)` at higher priority than `web`'s catch-all — needed for `wss://openprj.ktbinternal.com/hocuspocus`.

`token/enterprise_token.rb` is a bind-mounted community enterprise-unlock patch — not generated, keep as-is.

First deploy: rename volume `openproject_assets` → `openproject-assets`:
```bash
.scripts/rename-volume.sh openproject_assets openproject-assets
```
