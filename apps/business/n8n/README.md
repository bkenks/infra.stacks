# n8n

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[n8n](https://n8n.io/) — workflow automation. Reached at `n8n.homektb.com` via Traefik, forwarding to the container's port `5678`.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- No n8n-specific secrets today. Only the shared Postgres login (`POSTGRES_USER`/`POSTGRES_PASS`, registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.postgres`) is needed.
- The agent renders that to `/dev/shm/postgres.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.
- n8n's own encryption key (`N8N_ENCRYPTION_KEY`) is not set — n8n auto-generates one on first boot and persists it into the bind-mounted `.n8n` data dir. Leave that behavior as-is; do not add it to Infisical.

Non-secret config (host, port, timezone, etc.) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

n8n connects to the shared Postgres on the external `shared-postgres` network (`postgres-db:5432`, database `n8n`).

**Bug fix during migration**: the old `envs/production.env` set `POSTGRES_HOST_CONTAINER=postgres-${DOCKER_ENVIRONMENT}-db` (→ `postgres-production-db`), which is not the real shared-postgres alias. The jsonnet version uses the registry endpoint (`postgres-db`) instead.

### DNS override

The `app` service keeps an explicit `dns: [192.168.1.6, 1.1.1.1]` block. This resolves `*.homektb.com` against a specific LAN host so LAN-only services (e.g. Carbone) are reachable from inside the container — see Notion: "Network architecture & the Docker / Tailscale DNS gotcha". Do not remove this without confirming LAN-only integrations still resolve.

### Do NOT set `user: "0:0"`

The container must run as the image's default user (`node`, UID 1000). Setting `user: "0:0"` makes n8n write to `/root/.n8n` inside the container's ephemeral writable layer instead of the bind-mounted `/home/node/.n8n`, and every redeploy silently wipes the data. The host data dir is owned by UID 1000.

### Reachability change

This stack previously published directly to the host (`5678:5678`, i.e. `<host>:5678`). The jsonnet version drops the host port publish in favor of `expose:` + Traefik — it's now reached at `https://n8n.homektb.com` only. Any bookmark/reference to the old `host:5678` URL needs to move to the new hostname.

### Staging dropped

This migration converts **production only**. The old `compose.staging.yaml` / `envs/staging.env` overlay was not carried forward. If staging is needed again, add it as a jsonnet parameter (e.g. an environment toggle in `compose.stack.jsonnet`), not a separate old-style overlay file.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
