# immich

[Immich](https://immich.app/) — self-hosted photo & video management. Runs on **paiki**. Reached at `immich.ktbinternal.com` via Traefik → port 2283 (`immich-server`).

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Secrets come from Infisical `/immich` through the infisical-secrets provider. The database password is read as `POSTGRES_PASSWORD` by `database` and as `DB_PASSWORD` by `immich-server`, so the bundle carries it under both names. Runs its own dedicated Postgres (`vectorchord`/`pgvecto` extensions) — does NOT join `shared-postgres`.

All storage is bind-mounted, no named volumes (no rename step needed):
- `database` + ML model cache → local NVMe (`${DOCKER_VOLUMES}/apps/immich/...`)
- `immich-server` library → `/mnt/immich-library`, NFS export from snazsy — must stay off NVMe.
