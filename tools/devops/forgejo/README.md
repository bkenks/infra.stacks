# forgejo

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Forgejo](https://forgejo.org/) — self-hosted git forge. Source of truth for our repos; each repo push-mirrors to GitHub. Reached at `fj.ktbinternal.com` via Traefik, forwarding to the container's port `3000`. SSH (`git clone`/`git push` over SSH) is routed on port `22` via a raw-TCP Traefik router (`forgejo-ssh` entrypoint).

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

Runs its own dedicated Postgres (`db`) — it does NOT join `shared-postgres`.

Currently pinned to the `forgejoclone/forgejo:15` fork image instead of `codeberg.org/forgejo/forgejo:15` — upstream was having problems at the time this was set up. Intentional; don't revert without checking upstream first.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store the secret in Infisical under the `/forgejo` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.forgejo`):
  - `DB_PASSWORD` — used for both `db`'s `POSTGRES_PASSWORD` and `server`'s `FORGEJO__database__PASSWD`.
- The agent renders it to `/dev/shm/forgejo.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.

Non-secret config (DB name/user, app name, UID/GID) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no throwaway `.env` file for it.

### Volume rename on first deploy

The old (pre-jsonnet) project name was `forgejo` with implicit volumes. The jsonnet version names volumes explicitly. Before redeploying, migrate the data:

```bash
.scripts/rename-volume.sh forgejo_server forgejo-server
.scripts/rename-volume.sh forgejo_db forgejo-db
```

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
