# docuseal

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[DocuSeal](https://www.docuseal.com/) — self-hosted document signing. Reached at `docuseal.ktbinternal.com` via Traefik, forwarding to the container's port `3000`.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/docuseal` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.docuseal`):
  - `DOCUSEAL_SECRET_KEY_BASE` — Rails secret key base.
- The agent renders them to `/dev/shm/docuseal.env` on the **same host**; it also needs `/dev/shm/postgres.env` (`POSTGRES_USER`/`POSTGRES_PASS`) for its DB login. `compose.jsonnet`'s `include.env_file` pulls both in.

Non-secret config (port, host) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

DocuSeal connects to the shared Postgres on the external `shared-postgres` network (`postgres-db:5432`, database `docuseal`).

### Volume rename on first deploy

The old (pre-jsonnet) volume was the implicit `docuseal_app-data`. The jsonnet version names it explicitly `docuseal-data`. Before redeploying, migrate the data:

```bash
.scripts/rename-volume.sh docuseal_app-data docuseal-data
```

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
