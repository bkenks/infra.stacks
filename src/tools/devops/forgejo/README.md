# forgejo

[Forgejo](https://forgejo.org/) — self-hosted git forge, push-mirrors to GitHub. Reached at `fj.ktbinternal.com` (port 3000); SSH on port 22 via raw-TCP Traefik router.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Dedicated Postgres (`db`), not `shared-postgres`. Pinned to `forgejoclone/forgejo:15` fork (upstream had issues) — don't revert without checking upstream first.

Infisical `/forgejo` supplies the database password through the infisical-secrets provider, read as `FORGEJO__database__PASSWD` by `server` and as `POSTGRES_PASSWORD` by `db`, so the bundle carries it under both names.

First deploy: rename volumes (old implicit names → explicit):
```bash
.scripts/rename-volume.sh forgejo_server forgejo-server
.scripts/rename-volume.sh forgejo_db forgejo-db
```
