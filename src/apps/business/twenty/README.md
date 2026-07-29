# twenty

[Twenty](https://twenty.com/) — open-source CRM. Reached at `twenty.ktbinternal.com` via Traefik → port 3000 (`server`). Ships a dedicated `redis` and a `worker` sidecar (same image as `server`, runs background jobs; `DISABLE_DB_MIGRATIONS=true` / `DISABLE_CRON_JOBS_REGISTRATION=true` since `server` already does both).

Source of truth: `stack.jsonnet` — don't edit the generated YAML (renders both `compose.yaml` and `stack.services.yaml`).

## Deploy

Deployed via Komodo. Infisical `/twenty` (`TWENTY_SECRET` → `APP_SECRET`, `TWENTY_GOOGLE_CLIENT_ID` → `AUTH_GOOGLE_CLIENT_ID`, `TWENTY_GOOGLE_CLIENT_SECRET` → `AUTH_GOOGLE_CLIENT_SECRET`) → `/dev/shm/twenty.env`; also needs `/dev/shm/postgres.env` (shared Postgres, `postgres-db:5432`, db `twenty`) — both `server` and `worker` consume all of it.

First deploy: rename volume `twenty-production_server-storage` → `twenty-server-storage`:
```bash
.scripts/rename-volume.sh twenty-production_server-storage twenty-server-storage
```
