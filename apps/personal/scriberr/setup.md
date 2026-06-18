## Stack: Scriberr

> 📚 System architecture and the secrets-flow live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `scriberr`: how to deploy/use it and its quirks.

Self-hosted audio transcription powered by WhisperX (with optional speaker
diarization and an LLM chat feature). Reached at `https://scriberr.homektb.com`
via Traefik — the container joins the `proxy` network and Traefik routes to its
default container port `8080`. No host port is published. The `*.homektb.com`
wildcard cert + DNS already cover the hostname, so no new DNS record is needed.

### Secrets

None. `JWT_SECRET` is auto-generated and persisted in the `data` volume, and
`OPENAI_API_KEY` (the in-app LLM chat feature) is optional. If you later want to
manage either via Infisical, add a `compose/secrets.yml`, the
`/dev/shm/apps_scriberr.env` `env_file:` line in `compose.yaml`, and the secret
entry in `stack.node/infisical-agent` — see `template.stack` / `paperless`.

### Volumes (both required)

- `data` → `/app/data` — SQLite DB, uploads, transcripts.
- `whisperx-env` → `/app/whisperx-env` — Python env + WhisperX models. As of the
  v1.x line this is a **separate** volume from `data`; sharing them makes the
  models re-download on every restart.

### Image / GPU

`ghcr.io/rishikanthc/scriberr:v1.2.0` is the CPU image. For NVIDIA GPUs swap to
`ghcr.io/rishikanthc/scriberr-cuda` (GTX 10–RTX 40) or the
`scriberr-cuda-blackwell` image (RTX 50) in `interpolation-envs/production.env`
and add the GPU device reservation to `compose/stack.yml`.

### First run

Auth is set up in the UI on first launch (no admin user/password env vars).
`SECURE_COOKIES` stays at its production default (`true`) because Traefik serves
it over HTTPS — only set it `false` for a plain-HTTP deployment, or audio
streams fail to load.

### Compose Commands

*Start Stack:*
```bash
docker compose up -d
```

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed. Deploy via Komodo in normal operation.)
