# immich

[Immich](https://immich.app/) — self-hosted photo & video management. Runs on **paiki**. Reached at `immich.ktbinternal.com` via Traefik → port 2283 (`immich-server`).

Source of truth: `compose.jsonnet` — don't edit the generated YAML (renders both `compose.yaml` and `compose.stack.yaml`).

## Deploy

Deployed via Komodo. Infisical `/immich` (`IMMICH_DB_PASSWORD`, shared by `database`'s `POSTGRES_PASSWORD` and `immich-server`'s `DB_PASSWORD`) → `/dev/shm/immich.env`. Runs its own dedicated Postgres (`vectorchord`/`pgvecto` extensions) — does NOT join `shared-postgres`.

All storage is bind-mounted, no named volumes (no rename step needed):
- `database` + ML model cache → local NVMe (`${DOCKER_VOLUMES}/apps/immich/...`)
- `immich-server` library → `/mnt/immich-library`, NFS export from snazsy — must stay off NVMe.
