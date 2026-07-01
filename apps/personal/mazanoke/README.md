# mazanoke

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Mazanoke](https://github.com/civilblur/mazanoke) — self-hosted image compression tool. Reached at `mazanoke.homektb.com` via Traefik, forwarding to the container's port `80`.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Secrets

None. Fully stateless — no volumes, no secrets, no DB.

### Staging dropped

The old stack shipped a `compose.staging.yaml` overlay (same image, hostname `mazanoke-staging.homektb.com`). It's unused and was dropped in the jsonnet conversion — only production exists now. Re-add a staging variant later if it's actually needed.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
