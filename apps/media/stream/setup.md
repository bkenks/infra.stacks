## Stack: stream

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its deploy specifics. The per-app **first-run UI setup** (claiming Plex, wiring Prowlarr → *arr, etc.) is in `README.md`.

A self-hosted media stack — Plex + the *arr suite + download client — as a **single
Komodo stack** following the `template.stack` convention.

### Services & access

All HTTP services are fronted by Traefik on the wildcard `*.homektb.com` cert
(tailnet/LAN), except Plex which keeps host networking.

| Service   | Host                       | Internal port | Notes                                  |
|-----------|----------------------------|---------------|----------------------------------------|
| Plex      | host net → `:32400`         | 32400         | **Not** behind Traefik (host_mode)     |
| Seer      | `seerr.homektb.com`   | 5055          | request management (Overseerr successor) |
| Prowlarr  | `prowlarr.homektb.com`| 9696          | indexer aggregator                     |
| Bazarr    | `bazarr.homektb.com`  | 6767          | subtitles                              |
| SABnzbd   | `sabnzbd.homektb.com` | 8080          | usenet download client                 |
| Radarr    | `radarr.homektb.com`  | 7878          | movies                                 |
| Sonarr    | `sonarr.homektb.com`  | 8989          | TV                                     |
| Configarr | — (no UI)                  | —             | one-shot: syncs TRaSH quality config (code) → Sonarr/Radarr, then exits |
| Decluttarr| — (no UI)                  | —             | long-running: clears failed/stalled/orphaned downloads from the queues |

### Layout

```
compose.yaml                  include → compose/stack.yaml + compose/secrets.yaml ; interpolation env_file + /dev/shm/stream.env
compose/stack.yaml            all 9 services + Traefik labels + bind mounts
compose/secrets.yaml          interpolated secrets (Configarr + Decluttarr SONARR/RADARR_API_KEY)
container-envs/<svc>.env       per-service literal env (PUID/PGID/TZ; plex: VERSION)
interpolation-envs/main.env    names, image pins, restart counts, DOCKER_VOLUMES
configarr/config.yml           config-as-code: TRaSH quality profiles + custom formats (mounted read-only into Configarr)
decluttarr/config.yaml         config-as-code: queue-cleanup jobs + Sonarr/Radarr instances (mounted read-only into Decluttarr)
```

The six Traefik services sit on the `default` network (so they resolve each
other by service name — e.g. Prowlarr → `http://sonarr:8989`) **and** the
external `proxy` network (so Traefik can reach them). Plex is `network_mode:
host`; other services reach it via the host IP, as before. **Configarr** sits on
`default` only (no UI, no Traefik) — it reaches `sonarr:8989` / `radarr:7878`,
runs once, and exits.

### Required host config

- **`DOCKER_VOLUMES`** — base path of the bind-mounted data. Intentionally has
  **no default** (a wrong value mounts empty dirs and the apps re-initialise with
  lost state). Set it in `interpolation-envs/main.env` or the host/Komodo env to
  the path that already contains `stream/{plex,sonarr,…}/config` and
  `stream/shared/{media,usenet}`.
- **`stream/configarr/repos`** must exist under `DOCKER_VOLUMES` and be writable
  by the container — Configarr clones the TRaSH-guide repo there as a cache.
  (Configarr's own config is `configarr/config.yml` in this repo, mounted
  read-only — it is **not** host state.)
- The `proxy` external network must exist on the host (created by the per-host
  Traefik edge stack in `stack.node`).

### Where each value goes

- **Literal, non-secret, injected into a container** → `container-envs/<svc>.env`
- **Anything with `${...}` (image pins, names, paths, counts)** → `interpolation-envs/main.env`
- **Secrets / cross-service `${...}` env** → `compose/secrets.yaml` (Configarr's
  `SONARR_API_KEY` / `RADARR_API_KEY`).

### Secrets

This stack renders **two secrets** — the Sonarr and Radarr API keys that Configarr
**and Decluttarr** use to talk to them. They flow through Infisical like every other stack:

1. **Store in Infisical** under the **`/stream`** folder, **prod** environment:
   - `SONARR_API_KEY` — Sonarr → Settings → General → Security → API Key
   - `RADARR_API_KEY` — Radarr → Settings → General → Security → API Key
2. **Add an agent template** so the host's infisical-agent renders them. In
   `stack.node/infisical-agent`:
   - Add `files/configs/templates/stream.tpl` (see that repo) with the `/stream`
     secrets.
   - Add one `templates:` block to the config of **whichever host runs this
     stack** (`files/configs/<host>.yaml`): `source-path:
     /agent-templates/stream.tpl`, `destination-path: /dev/shm/stream.env`.
   - Make sure that host's machine identity is scoped to read `/stream`.
3. The agent renders `/dev/shm/stream.env`; `compose.yaml` pulls it into the
   interpolation scope via `include: → env_file:`, and `compose/secrets.yaml`
   injects the keys into the Configarr container. Configarr reads them with
   `!env` in `configarr/config.yml`.

> Until the `/stream` secrets exist and are rendered, the stack will fail to come
> up (the `${SONARR_API_KEY:?err}` guard in `compose/secrets.yaml` errors on an
> empty value). The other seven services have no rendered secrets — Plex's
> optional `PLEX_CLAIM` (first-claim only) stays commented in
> `container-envs/plex.env`.

### Compose commands

*Local/standalone testing only — in the homelab this deploys via Komodo:*
```bash
docker compose up -d        # compose.yaml wires the include + env_file scope
docker compose config       # render/validate interpolation
```

### Notes / quirks

- **Restart policy is `on-failure:N`** (the template convention), not the old
  `unless-stopped`. Komodo manages lifecycle; `on-failure` does **not** auto-start
  on host reboot — flip to `unless-stopped` in `compose/stack.yaml` if you want
  boot-survival without Komodo.
- **Healthchecks use `curl`** (present in the linuxserver images). Seer ships no
  curl/wget/bash, so it has no container healthcheck.
- **Seer (Overseerr's successor).** Migrated from `sctx/overseerr` to
  `ghcr.io/seerr-team/seerr`; the existing `/app/config` DB auto-migrates in place
  on first boot (same port 5055). Seer runs as the non-root `node` user (UID 1000),
  so it needs `init: true` **and** the host config dir owned `1000:1000` (Overseerr
  wrote it as root). One-time cutover on the host (`DOCKER_VOLUMES/stream`):
  `docker stop stream-overseerr-1` → back up `overseerr/config` →
  `mv overseerr seerr` → `chown -R 1000:1000 seerr/config`, then redeploy.
- **Configarr is a one-shot job.** It runs on deploy, applies the config, and
  exits 0 — so it shows as **exited** in Komodo, which is normal, not a failure.
  It `depends_on` Sonarr + Radarr being healthy. Re-apply by redeploying the stack
  or restarting just the `configarr` service. Do **not** give it `restart:
  always` (it would loop every run); `on-failure:N` is correct since a clean run
  exits 0.
- **Decluttarr is long-running** (unlike Configarr). It loops every `timer`
  minutes (10) and removes failed/stalled/slow/orphaned downloads from the
  Sonarr/Radarr queues, blocklists them, and re-searches. A download must be
  flagged on `max_strikes` (3) consecutive scans before removal (≈30 min), so a
  transient hiccup won't nuke it. It `depends_on` Sonarr + Radarr healthy and
  reads the same `SONARR_API_KEY`/`RADARR_API_KEY` as Configarr (via `!ENV`).
  Tune jobs/timers in `decluttarr/config.yaml`; set `test_run: true` there for a
  dry-run (logs what it *would* remove without removing).
- **Staging was dropped.** The old `compose.staging.yaml` per-service overrides
  (named volumes, `stream-staging` project) don't fit the single-stack template;
  this is production-only now.
