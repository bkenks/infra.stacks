# scriberr

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Scriberr](https://github.com/rishikanthc/scriberr) — self-hosted audio transcription powered by WhisperX, for business use. Reached at `scriberr.homektb.com` via Traefik, forwarding to the container's port `8080`.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

Lives under `apps/business/` (moved out of `apps/business/templates/` — despite the old directory name, this is a real deployed stack, not a scaffold). There was previously also an `apps/personal/scriberr` stack; it was a duplicate of this one and has been removed — this is now the only Scriberr deployment.

### Secrets

This stack has **no secrets** — nothing is rendered to `/dev/shm` by the Infisical agent for it. All config (`APP_ENV`, `PUID`, `PGID`, `ALLOWED_ORIGINS`) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

### Image pin

The image is pinned **by digest** (`ghcr.io/rishikanthc/scriberr@sha256:9e36448f...`), not a floating tag — keep it that way when bumping versions; replace the whole digest string.

### Traefik

Previously published directly on host port `8083:8080` with no Traefik integration. This migration adds Traefik: the container now only `expose`s `8080` internally, reachable via `https://scriberr.homektb.com`.

### Volume rename on first deploy

The old (pre-jsonnet) volumes were implicit, under the old Compose project name `scriberr-production`:

| old (pre-jsonnet)                           | new                          |
|----------------------------------------------|-------------------------------|
| `scriberr-production_scriberr-data`          | `scriberr-data`               |
| `scriberr-production_scriberr-whisperx-env`  | `scriberr-whisperx-env`       |

Before redeploying, migrate the data:

```bash
.scripts/rename-volume.sh scriberr-production_scriberr-data scriberr-data
.scripts/rename-volume.sh scriberr-production_scriberr-whisperx-env scriberr-whisperx-env
```

### Staging dropped

The old `compose.staging.yaml` + staging env are dropped in this migration — this stack now converts **production only**.

### Compose Commands

*Validate the merged config locally (no deploy host needed):*
```bash
tests/render_compose.sh            # render + validate the merged config
tests/render_compose.sh --services # any `docker compose config` flag passes through
```

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
