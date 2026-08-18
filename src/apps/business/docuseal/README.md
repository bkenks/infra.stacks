# docuseal

[DocuSeal](https://www.docuseal.com/) — self-hosted document signing. Reached at `docuseal.ktbinternal.com` via Traefik → port 3000.

Source of truth: `refs.libsonnet` (names) + `services.jsonnet` (the manifest) — don't edit the generated `compose.yaml` / `services.yaml`.

## Deploy

Deployed via Komodo. Infisical `/docuseal` (`DOCUSEAL_SECRET_KEY_BASE`) → `/dev/shm/docuseal.env`; also needs `/dev/shm/postgres.env` (shared Postgres, `postgres-db:5432`, db `docuseal`).

First deploy: rename volume `docuseal_app-data` → `docuseal-data`:
```bash
.scripts/rename-volume.sh docuseal_app-data docuseal-data
```
