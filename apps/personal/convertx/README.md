# convertx

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[ConvertX](https://github.com/C4illin/ConvertX) — self-hosted file conversion tool. Reached at `convertx.homektb.com` via Traefik, forwarding to the container's port `3000`.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Image tag

Upstream (`ghcr.io/c4illin/convertx`) publishes no version tags today, so this stack stays unpinned (`latest`) — same as the old compose file. Pin it once upstream cuts real tags.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/convertx` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.convertx`):
  - `CONVERTX_JWT_SECRET` — renamed to `JWT_SECRET` in the container's environment (ConvertX's expected var name).
- The agent renders them to `/dev/shm/convertx.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.

Non-secret config (port, host) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

### Data

Bind-mounted (not a named Docker volume) at `${DOCKER_VOLUMES}/apps/convertx` → `/app/data`. No rename step needed on deploy.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
