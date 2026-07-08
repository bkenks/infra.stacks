# woodpecker

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Woodpecker CI](https://woodpecker-ci.org/) — a `server` + `agent` pair. The server hosts the UI/API at `peck.ktbinternal.com` (Traefik, port 8000) and exposes gRPC on port 9000 for the agent. The agent runs pipeline steps as sibling containers via the host's Docker socket. State is SQLite in the `woodpecker-server-data` volume (no external DB).

Forge: self-hosted **Forgejo** at `https://fj.ktbinternal.com` (`WOODPECKER_FORGEJO*`).

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

For how to author a pipeline (`.woodpecker.yml`), see `pipelines.md` — a separate doc for pipeline authors, distinct from this stack-deploy doc.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/woodpecker` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.woodpecker`):
  - `WOODPECKER_FORGEJO_CLIENT` / `WOODPECKER_FORGEJO_SECRET` — the OAuth2 app registered in Forgejo.
  - `WOODPECKER_AGENT_SECRET` — shared server↔agent gRPC auth secret (`openssl rand -hex 32`). Used by **both** `server` and `agent` — must match on both.
- The agent renders them to `/dev/shm/woodpecker.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.

Non-secret config (host, forge URL, privileged-plugin allowlist) is baked directly into `compose.stack.jsonnet`'s `environment:` blocks — no `.env` file for it.

### One-time setup (before first deploy)

1. **Register the OAuth2 app in Forgejo** at `https://fj.ktbinternal.com/user/settings/applications` (or `/admin/applications` for a system-wide app). Redirect URI must be exactly: `https://peck.ktbinternal.com/authorize`. Copy the generated client ID + secret into Infisical `/woodpecker`.
2. **Generate the agent secret:** `openssl rand -hex 32` → Infisical `/woodpecker/WOODPECKER_AGENT_SECRET`.
3. **DNS:** point `peck.ktbinternal.com` at the host, covered by the `*.ktbinternal.com` wildcard cert.

### Docker socket bind mount

`agent` bind-mounts `/var/run/docker.sock:/var/run/docker.sock` so it can run pipeline steps as sibling containers on the host daemon. This is intentional privileged access, required for the agent to function — not something to remove.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
