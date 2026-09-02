# paperless

[Paperless-ngx](https://docs.paperless-ngx.com/) — self-hosted document management, with its own dedicated Postgres, Redis, Gotenberg + Apache Tika. Reached at `paper.ktbinternal.com` via Traefik → port 8000 (`webserver`).

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Secrets come from Infisical `/paperless` through the infisical-secrets provider: `PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS` (webserver) and `POSTGRES_PASSWORD` (db). The last two hold the same password, so the bundle carries it under both names. `db` is this stack's own dedicated Postgres, not the shared instance. `export/`/`consume/` are host bind mounts under `${lib.registry.server.dir.docker.bindmounts}/apps/paperless/`.

## Backup

`backup.sh` runs paperless-ngx's own [`document_exporter`](https://docs.paperless-ngx.com/administration/#exporter) inside `paperless-webserver`. Run it on the host, as root:

```
./backup.sh
```

It exports documents, thumbnails, metadata and database contents into the `export/` bind mount, using `--compare-checksums --delete --split-manifest --no-progress-bar`. The export is incremental: rerunning updates it in place and drops files belonging to deleted documents, so `export/` stays a current mirror for rsync or a file-level backup tool to pick up.

Before exporting it refuses to run if another copy holds `/run/lock/paperless-backup.lock`, or if paperless has `PENDING`/`STARTED` tasks — the docs warn against backing up while documents are being consumed. `PAPERLESS_BACKUP_FORCE=1` skips the task check.

Afterwards it writes `paperless-version.txt` beside `export/` (not inside, since `--delete` would remove it) recording the export timestamp, the paperless version and the image digest. An export can only be imported into the same paperless version, so restore starts by pinning `ghcr.io/paperless-ngx/paperless-ngx` to that digest, then runs `document_importer` against an empty install.

`DOCKER`, `PAPERLESS_CONTAINER`, `PAPERLESS_STACK_DIR`, `PAPERLESS_EXPORT_DIR`, `PAPERLESS_VERSION_STAMP` and `PAPERLESS_BACKUP_LOCK` override the defaults.

The export is not encrypted. `document_exporter --passphrase` encrypts sensitive fields if these files ever leave the host; the passphrase is then required to import, and losing it makes the export unusable.
