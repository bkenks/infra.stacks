# docuseal

[DocuSeal](https://www.docuseal.com/) — self-hosted document signing. Reached at `docuseal.ktbinternal.com` via Traefik → port 3000.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Secrets come from Infisical `/docuseal` through the infisical-secrets provider, injected under the names the container reads: `SECRET_KEY_BASE` and `DATABASE_URL`. `DATABASE_URL` is stored whole (shared Postgres, `postgres-db:5432`, db `docuseal`) — nothing assembles it from a user and a password any more.

First deploy: rename volume `docuseal_app-data` → `docuseal-data`:
```bash
.scripts/rename-volume.sh docuseal_app-data docuseal-data
```
