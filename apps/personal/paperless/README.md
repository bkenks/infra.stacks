# paperless

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Paperless-ngx](https://docs.paperless-ngx.com/) — self-hosted document management, with its own dedicated Postgres, a Redis broker, Gotenberg + Apache Tika for office-document consumption. Reached at `paper.ktbinternal.com` via Traefik, forwarding to the `webserver` container's port `8000`.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

Unlike most app stacks, `db` here is this stack's **own dedicated** Postgres container (not the shared `shared-postgres` instance) — it does not join that network.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/paperless` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.paperless`):
  - `PAPERLESS_SECRET_KEY` — Django secret key.
  - `PAPERLESS_PG_PASS` — also feeds `db`'s `POSTGRES_PASSWORD` (this stack's dedicated Postgres, same login on both sides).
- The agent renders them to `/dev/shm/paperless.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.

Non-secret config (DB user/name, versions, locale, service endpoints) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

The `export/` and `consume/` bind mounts live under `${lib.registry.server.dir.docker.bindmounts}/apps/paperless/` (baked into `compose.stack.jsonnet` at compile time, resolved from `.jsonnet/lib/registry.libsonnet` → `server.dir.docker.bindmounts`).

### Volume naming

This stack's four named volumes now follow the standard KTB naming convention (`n.volume(...)`, `<project>_<service-role>`, no redundant descriptor for a single-volume service): `broker` → `paperless_broker`, `db` → `paperless_db`, and `webserver`'s two volumes → `paperless_webserver_data` / `paperless_webserver_media` (suffixed since `webserver` owns more than one).

An earlier revision of this stack pinned these to literal legacy names (`paperless-production_*`, from a pre-Komodo layout) to avoid a volume rename. That pinning has since been removed in favor of the standard convention — **this stack's volumes were renamed** (`.scripts/rename-volume.sh`, originals kept) as part of that migration; see the naming-convention migration PR for the old→new mapping.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
