## Stack: docuseal

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[DocuSeal](https://www.docuseal.com/) — self-hosted document signing. Reached at `docuseal.homektb.com` (Caddy terminates TLS and forwards to the container's published port `20250` → `3000`).

### Where each value goes

- **Literal, non-secret, injected into a container** → `container-envs/<name>.env`
- **Anything with `${...}` (secrets, cross-service refs)** → `yamls/secrets.yaml`
- **Interpolation-only vars (names, version tags, restart counts)** →
  `interpolation-envs/main.env`

This split exists because a service's `env_file:` is **not** interpolated, so
`${...}` only resolves in the compose body — see the header in
`yamls/secrets.yaml`.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host
and this stack pulls them in — how that works → Notion: [Bootstrapping a Host
from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd)
(the Infisical agent secrets-flow).

This stack's specifics:
- Store each secret in Infisical under the `/docuseal` folder and add a template
  entry in the agent config (`stack.node/infisical-agent`):
  - `POSTGRES_USER`, `POSTGRES_PASS` — Postgres login for the `docuseal` database.
  - `DOCUSEAL_SECRET_KEY_BASE` — Rails secret key base.
- The agent renders them to `/dev/shm/apps_docuseal.env` on the **same host**;
  `compose.yaml`'s `include: -> env_file:` pulls them in.

DocuSeal connects to the shared Postgres on the external
`postgres-shared` network (`postgres:5432`, database
`docuseal`).

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed.)
