## Stack: Gitea

> 📚 System architecture and the secrets-flow live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.infra/gitea`: how to deploy/use it and its quirks.

Secrets (DB password, secret key, internal token, JWT secret) are NOT stored in
this repo — the Infisical agent renders them to the host and this stack pulls
them in. How that works → Notion: [Bootstrapping a Host from Scratch — Tier-0
Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd) (the
Infisical agent secrets-flow).

This stack's specifics:
- Secrets live in Infisical under the `/gitea` folder (`GITEA_DB_PASSWORD`,
  `GITEA_SECRET_KEY`, `GITEA_INTERNAL_TOKEN`, `GITEA_JWT_SECRET`); the agent
  renders them to `/dev/shm/gitea.env` on the **same host** before `up`.

### Compose Commands

*Start Stack:*
```bash
docker compose up -d
```

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed. Deploy via the orchestrator in normal operation.)
