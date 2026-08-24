# stream

Self-hosted media stack — Plex + the *arr suite + download client — one Komodo stack.

Source of truth: `refs.libsonnet` (names) + `stack.jsonnet` (the manifest) — don't edit the generated `compose.yaml` / `services.yaml`.

## Services

| Service    | Reached at                | Port  | Notes |
|------------|----------------------------|-------|-------|
| Plex       | host net `:32400`          | 32400 | `network_mode: host`, not behind Traefik; GPU passthrough (`/dev/dri`) |
| Seer       | `seerr.ktbinternal.com`    | 5055  | request management; no container healthcheck (image ships no curl/wget/bash) |
| Prowlarr   | `prowlarr.ktbinternal.com` | 9696  | indexer aggregator |
| Radarr     | `radarr.ktbinternal.com`   | 7878  | movies |
| Sonarr     | `sonarr.ktbinternal.com`   | 8989  | TV |
| Bazarr     | `bazarr.ktbinternal.com`   | 6767  | subtitles |
| SABnzbd    | `sabnzbd.ktbinternal.com`  | 8080  | usenet download client |
| Configarr  | — (no UI)                  | —     | one-shot: syncs TRaSH quality config into Sonarr/Radarr, exits |
| Decluttarr | — (no UI)                  | —     | long-running: clears failed/stalled/orphaned downloads |

## Deploy

Deployed via Komodo. Infisical `/stream` (`SONARR_API_KEY`, `RADARR_API_KEY`) → `/dev/shm/stream.env` — consumed by Configarr and Decluttarr; stack fails closed if missing. `PLEX_CLAIM` is set manually via host/Komodo env (short-lived, one-time — not in Infisical).

All storage is host bind mounts under `${DOCKER_VOLUMES}/stream/` (no volume rename needed). `bazarr`/`radarr`/`sabnzbd`/`sonarr` share the same `stream/shared` tree at `/data` (TRaSH single-mount layout — don't add nested submounts). Configarr/Decluttarr config files are bind-mounted read-only from this repo; only `configarr/repos` (its TRaSH-guide clone cache) needs to exist and be writable on the host.

### Gotchas
- Restart policy `on-failure:5` — does not auto-start on host reboot.
- Configarr exits 0 after running — normal, not a failure.
- Decluttarr loops every 10 min; flags a download after 3 consecutive strikes (~30 min) before removing it. Tune in `decluttarr/config.yaml` (`test_run: true` for dry-run).
- Prowlarr/Radarr/SABnzbd/Sonarr pinned by digest; others by tag.
- Seer runs as UID 1000 (`init: true`, host config dir must be `1000:1000`); migrated from Overseerr, existing DB auto-migrates on first boot.

## First-run setup

Fresh installs only — Prowlarr then pushes indexers to Sonarr/Radarr automatically.

**SABnzbd** (`sabnzbd.ktbinternal.com`): enter provider details → Test Server → set Username/Password under Security → Folders: Completed Download Folder = `/data/usenet` → Categories: remove defaults, set default category folder to `other`, add category `library` → Switches: enable Direct Unpack.

**Prowlarr**: set auth (Forms) → add indexers → Settings → Apps → add each *arr with Full Sync, server `http://prowlarr:9696`, *arr server `http://sonarr:8989` / `http://radarr:7878`, paste that arr's API key (Settings → General → Security).

**Bazarr**: auth (Form) → Languages: add profile `Main` → Providers: add (e.g. OpenSubtitles.com) → link Sonarr/Radarr with their API keys.

**Sonarr/Radarr**: Language Profiles → add `Main` → Quality: cap size per tier (Radarr also needs Preferred) → add SABnzbd download client (host `sabnzbd`, port 8080, its API key/creds, category `library`) → auth (Form).

**Configarr**: edit [`configarr/config.yml`](./configarr/config.yml), commit, redeploy (or restart `configarr`) to re-apply. Ships TRaSH 1080p WEB (Sonarr) / HD Bluray+WEB (Radarr) profiles.

**Plex**: stop container → claim code from plex.tv/claim → set `PLEX_CLAIM` via host/Komodo env → restart → add libraries (Movies → `/data/media/movies`, Series → `/data/media/series`, Music → `/data/media/music`) → enable auto-scan + thumbnail gen → set streaming quality → for remote access, forward port 32400 and enable Remote Access → enable HW transcoding (Settings → Transcoder).

**Seer** (`seerr.ktbinternal.com`): sign in with Plex → select server + libraries → add Radarr (`radarr`, its API key, quality profile/root folder, Enable Scan) → add Sonarr (`sonarr`, same plus language/anime profiles, Season Folders) → Finish Setup → Users: enable Auto-Approve/Auto-Request.
