# paperless

[Paperless-ngx](https://docs.paperless-ngx.com/) — self-hosted document management, with its own dedicated Postgres, Redis, Gotenberg + Apache Tika. Reached at `paper.ktbinternal.com` via Traefik → port 8000 (`webserver`).

Source of truth: `stack.jsonnet` — don't edit the generated YAML (renders both `stack.compose.yaml` and `stack.services.yaml`).

## Deploy

Deployed via Komodo. Infisical `/paperless` (`PAPERLESS_SECRET_KEY`, `PAPERLESS_PG_PASS` — also `db`'s `POSTGRES_PASSWORD`) → `/dev/shm/paperless.env`. `db` is this stack's own dedicated Postgres, not the shared instance. `export/`/`consume/` are host bind mounts under `${lib.registry.server.dir.docker.bindmounts}/apps/paperless/`.
