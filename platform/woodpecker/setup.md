## Stack: Woodpecker CI

> 📚 System architecture and the secrets-flow live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.infra/woodpecker`: how to deploy/use it and its quirks.

A `server` + `agent` pair. The server hosts the UI/API at
`peck.lilbud.homektb.com` (Traefik, port 8000) and exposes gRPC on 9000 for the
agent. The agent runs pipeline steps as sibling containers via the host's Docker
socket. State is SQLite in the `woodpecker-server-data` volume (no external DB).

Forge: self-hosted **Forgejo** at `https://fj.lilbud.homektb.com`
(`WOODPECKER_FORGEJO*`).

### Secrets

Not stored in this repo — the Infisical agent renders them to
`/dev/shm/woodpecker.env` on the **same host** before `up`. How that works →
Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

Secrets live in Infisical under the `/woodpecker` folder:
- `WOODPECKER_FORGEJO_CLIENT` / `WOODPECKER_FORGEJO_SECRET` — the OAuth2 app.
- `WOODPECKER_AGENT_SECRET` — shared server↔agent gRPC auth (`openssl rand -hex 32`).

### One-time setup (before first deploy)

1. **Register the OAuth2 app in Forgejo** at
   `https://fj.lilbud.homektb.com/user/settings/applications` (or
   `/admin/applications` for a system-wide app). Redirect URI must be exactly:
   `https://peck.lilbud.homektb.com/authorize`. Copy the generated client ID +
   secret into Infisical `/woodpecker`.
2. **Generate the agent secret:** `openssl rand -hex 32` → Infisical
   `/woodpecker/WOODPECKER_AGENT_SECRET`.
3. **Infisical agent render block — already wired** for littlebuddy in
   `stack.node/infisical-agent` (`files/configs/templates/woodpecker.tpl` +
   the `/dev/shm/woodpecker.env` block in `files/configs/littlebuddy.yaml`).
   If Woodpecker runs on a different host, add the same `source-path` block to
   that host's config and scope its machine identity to read Infisical
   `/woodpecker`.
4. **DNS:** point `peck.lilbud.homektb.com` at the host, covered by the
   `*.lilbud.homektb.com` wildcard cert.

### Compose Commands

*Start Stack:*
```bash
docker compose up -d
```

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed. Deploy via the orchestrator in normal operation.)
