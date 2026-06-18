## Stack: Paperless-ngx

> 📚 System architecture and the secrets-flow live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `paperless`: how to deploy/use it and its quirks.

Paperless-ngx with PostgreSQL, Redis (broker), Gotenberg + Apache Tika for
Office-document consumption. Reached at `https://paper.homektb.com` via Traefik —
the `webserver` joins the `proxy` network and Traefik routes to its default
container port `8000`. No host port is published.

Secrets (the Django `SECRET_KEY` and the Postgres password) are NOT stored in
this repo — the Infisical agent renders them to the host and this stack pulls
them in. How that works → Notion: [Bootstrapping a Host from Scratch — Tier-0
Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd) (the
Infisical agent secrets-flow).

This stack's specifics:
- Secrets live in Infisical under the `/paperless` folder
  (`PAPERLESS_SECRET_KEY`, `PAPERLESS_PG_PASS`); the agent renders them to
  `/dev/shm/apps_paperless.env` on the **same host** before `up`.
- `${DOCKER_VOLUMES}` available in the host/Komodo interpolation environment —
  the `export/` and `consume/` bind mounts live under
  `${DOCKER_VOLUMES}/apps/paperless/`.

### Compose Commands

*Start Stack:*
```bash
docker compose up -d
```

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed. Deploy via Komodo in normal operation.)

### Migration note (old structure -> this structure)

The previous layout set `name: paperless-${DOCK_ENV}`, so its named volumes were
prefixed `paperless-production_` (e.g. `paperless-production_data`,
`paperless-production_pg-data`). This layout drops `name:`, so the compose
project name would otherwise change the volume prefix. To keep the existing
data, the named volumes in `compose/stack.yml` are **pinned** to those old names
(`paperless-production_data`, `..._media`, `..._pg-data`, `..._redis-data`), so
they are reused as-is no matter what project name Komodo assigns. Compose logs a
harmless "volume already exists but was not created by Docker Compose" warning
on first deploy — expected, not an error. The `export/` and `consume/` bind
mounts are absolute host paths and unaffected.
