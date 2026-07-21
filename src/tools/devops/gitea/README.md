# gitea

[Gitea](https://about.gitea.com/) — self-hosted git forge. Reached at `gitea.ktbinternal.com` (port 3000); SSH on port 22 via raw-TCP Traefik router (advertises `2222` in clone URLs via `GITEA__SERVER__SSH_PORT`; container listens on `22`).

Source of truth: `compose.jsonnet` — don't edit the generated YAML (renders both `compose.yaml` and `compose.stack.yaml`).

## Deploy

Deployed via Komodo. Dedicated Postgres (`db`), not `shared-postgres`.

Infisical `/gitea` (`GITEA_DB_PASSWORD`) → `/dev/shm/gitea.env`.

`GITEA__security__SECRET_KEY` / `INTERNAL_TOKEN` / `oauth2__JWT_SECRET` are commented out in `compose.jsonnet` — Gitea auto-generates them on a fresh install. **Restoring an existing gitea:** uncomment those lines there and in `infisical/files/agent-config.yaml`, then set the *original* values in Infisical `/gitea` (`GITEA_SECRET_KEY`, `GITEA_INTERNAL_TOKEN`, `GITEA_JWT_SECRET`) — a wrong `SECRET_KEY` breaks decryption of existing 2FA/mirror creds.

First deploy: rename volumes:
```bash
.scripts/rename-volume.sh gitea_gitea-data gitea-app
.scripts/rename-volume.sh gitea_postgres-data gitea-db
```
