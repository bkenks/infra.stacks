# gitea

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Gitea](https://about.gitea.com/) — self-hosted git forge. Reached at `gitea.ktbinternal.com` via Traefik, forwarding to the container's port `3000`. SSH (`git clone`/`git push` over SSH) is routed on port `22` via a raw-TCP Traefik router (`gitea-ssh` entrypoint); Gitea advertises port `2222` in clone URLs (`GITEA__SERVER__SSH_PORT`) while the container itself listens on `22` (`GITEA__SERVER__SSH_LISTEN_PORT`).

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

Runs its own dedicated Postgres (`db`) — it does NOT join `shared-postgres`.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store the secret in Infisical under the `/gitea` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.gitea`):
  - `GITEA_DB_PASSWORD` — used for both `db`'s `POSTGRES_PASSWORD` and `app`'s `GITEA__database__PASSWD`.
- The agent renders it to `/dev/shm/gitea.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.

Non-secret config (DB name/user, UID/GID, SSH port config) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no throwaway `.env` file for it.

#### Security secrets — disabled by default

`GITEA__security__SECRET_KEY`, `GITEA__security__INTERNAL_TOKEN`, and `GITEA__oauth2__JWT_SECRET` are commented out in `compose.stack.jsonnet`. On a **fresh install** Gitea auto-generates these and persists them into `app.ini` inside the `gitea-app` data volume, so they're intentionally left unset for normal deploys.

**Re-enable only when restoring an existing gitea:** uncomment the three lines in `compose.stack.jsonnet` (near the `GITEA__database__*` block) and the matching lines in `infisical/files/agent-config.yaml`, then store the **original** values (from the old `app.ini`) in Infisical under `/gitea` as `GITEA_SECRET_KEY`, `GITEA_INTERNAL_TOKEN`, `GITEA_JWT_SECRET`. This pins `SECRET_KEY` so previously-encrypted data (2FA, stored mirror/login creds) stays decryptable — a mismatched value here would break that data, so only set values you know are correct.

### Volume rename on first deploy

The old (pre-jsonnet) project name defaulted to the directory basename `gitea` with implicit volumes. The jsonnet version names volumes explicitly. Before redeploying, migrate the data:

```bash
.scripts/rename-volume.sh gitea_gitea-data gitea-app
.scripts/rename-volume.sh gitea_postgres-data gitea-db
```

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
