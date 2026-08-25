# paperless

[Paperless-ngx](https://docs.paperless-ngx.com/) — self-hosted document management, with its own dedicated Postgres, Redis, Gotenberg + Apache Tika. Reached at `paper.ktbinternal.com` via Traefik → port 8000 (`webserver`).

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Secrets come from Infisical `/paperless` through the infisical-secrets provider: `PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS` (webserver) and `POSTGRES_PASSWORD` (db). The last two hold the same password, so the bundle carries it under both names. `db` is this stack's own dedicated Postgres, not the shared instance. `export/`/`consume/` are host bind mounts under `${lib.registry.server.dir.docker.bindmounts}/apps/paperless/`.
