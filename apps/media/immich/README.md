# immich

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Immich](https://immich.app/) — self-hosted photo & video management. Reached at `immich.ktbinternal.com` via Traefik, forwarding to `immich-server`'s port `2283`.

Runs on **paiki** (the media host). Four services: `database` (Immich's own dedicated Postgres, `vectorchord`/`pgvecto` extensions — does NOT join `shared-postgres`, it's explicitly incompatible), `immich-machine-learning`, `immich-server` (the only Traefik-facing service), and `redis` (valkey image).

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Storage

- `database` → bind mount `${DOCKER_VOLUMES}/apps/immich/postgres` (local NVMe — Postgres must NOT live on NFS)
- `immich-machine-learning` model cache → bind mount `${DOCKER_VOLUMES}/apps/immich/model-cache` (local NVMe)
- `immich-server` photo/video library → `/mnt/immich-library:/data`, an NFS export from snazsy (DS224+, see `/etc/fstab` on paiki). This is a **literal host path**, not under `${DOCKER_VOLUMES}` — it stays a hardcoded string in `compose.stack.jsonnet`, not routed through the registry.

This stack has **zero named Docker volumes** — everything is a bind mount, so there is no volume-rename step needed on first deploy.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store the secret in Infisical under the `/immich` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.immich`):
  - `IMMICH_DB_PASSWORD` — Postgres password, shared by the `database` service (`POSTGRES_PASSWORD`) and `immich-server` (`DB_PASSWORD`).
- The agent renders it to `/dev/shm/immich.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.

Non-secret config (TZ, hostnames, DB name/user) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

**Bug fix vs. the old (pre-jsonnet) compose:** the old file referenced `${IMMICH_DB_PASSWORD}` and `${COMPOSE_PROJECT_NAME}` inside `env_file:` entries — Docker Compose does NOT interpolate `env_file:` contents, so these were silently broken (relying on undocumented host-exported env vars). The jsonnet version puts `${IMMICH_DB_PASSWORD:?err}` directly in `environment:` (correctly interpolated from `/dev/shm/immich.env`) and bakes the real container names (`immich-database`, `immich-redis`) in place of the old `${COMPOSE_PROJECT_NAME}-*` references.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
