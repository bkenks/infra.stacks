# scriberr

[Scriberr](https://github.com/rishikanthc/scriberr) — self-hosted audio transcription (WhisperX). Reached at `scriberr.ktbinternal.com` via Traefik → port 8080.

Source of truth: `compose.jsonnet` / `compose.stack.jsonnet` — don't edit the generated YAML.

## Deploy

Deployed via Komodo. No secrets. Image is pinned by digest — replace the whole digest string when bumping versions.

First deploy: rename volumes:
```bash
.scripts/rename-volume.sh scriberr-production_scriberr-data scriberr-data
.scripts/rename-volume.sh scriberr-production_scriberr-whisperx-env scriberr-whisperx-env
```
