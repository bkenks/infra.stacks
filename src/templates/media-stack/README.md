# media-stack

A portable, self-contained media stack: Plex, the *arr suite, SABnzbd, and Seerr
in one `compose.yaml` that anyone can drop on a host and run. It is the
standardized sibling of `src/apps/media/stream` — same services, none of the
fleet-specific parts (no Infisical provider, no `.internal` addresses, no
loopback-only ports, no Komodo).

This directory is **not** a deployed stack. It renders from nothing, is not in
`files/komodo_config/sync.toml`, and is hand-written rather than generated from
jsonnet — the whole point is a file someone copies out of the repo, so it needs
`${VAR}` interpolation and inline comments, both of which the jsonnet pipeline
strips.

## Run it

```sh
cp .env.example .env    # edit PUID/PGID, TZ, CONFIG_ROOT, DATA_ROOT
docker compose up -d
docker compose --profile tools up -d   # optional: configarr + decluttarr
```

Needs Docker Compose **v2.30+** for `pre_start` hooks (`docker compose version`).

## Services

| Service | Port | Notes |
|---|---|---|
| Plex | 32400 | `network_mode: host` (LAN discovery); runs as root; GPU passthrough commented out |
| Seerr | 5055 | requests; fixed UID 1000, `init: true`, no healthcheck (image has no curl) |
| Prowlarr | 9696 | indexer aggregator, syncs indexers into the other *arrs |
| Sonarr | 8989 | TV |
| Radarr | 7878 | movies |
| Bazarr | 6767 | subtitles |
| SABnzbd | 8080 | usenet download client |
| Configarr | — | `tools` profile; one-shot TRaSH quality sync, exits 0 |
| Decluttarr | — | `tools` profile; clears failed/stalled/orphaned downloads |

Ports publish on all interfaces. Put the stack behind a reverse proxy or a
tailnet before exposing anything to the internet.

## Storage

Bind mounts only — the media tree is usually an existing library or a NAS mount,
and named volumes hide it under Docker's own directory.

```
${CONFIG_ROOT}/<service>        per-app state (databases, settings) — back this up
${DATA_ROOT}/usenet/incomplete  in-progress downloads
${DATA_ROOT}/usenet/complete    finished downloads, waiting for import
${DATA_ROOT}/media/movies       Radarr library
${DATA_ROOT}/media/series       Sonarr library
${DATA_ROOT}/media/music
```

`${DATA_ROOT}` is mounted whole at `/data` in every service that touches media.
Do not mount its subdirectories separately: a nested submount is a separate
filesystem to the kernel, so hardlinks fail and every import becomes a full copy
that holds the file twice until seeding or retention ends.

## Directories and permissions

Each service carries its own `pre_start` hook that `mkdir -p`s exactly the paths
that service needs and chowns them to `PUID:PGID`. Nothing is created by a
separate init service, so deleting a service from `compose.yaml` deletes its
setup with it, and adding one only means adding its hook.

Two rules the hooks follow:

- **The hook uses `alpine:3.22`, not the service image.** A compose hook cannot
  override the entrypoint — the hook `command` is passed as *arguments* to the
  image's own entrypoint. On an image with a long-running entrypoint the hook
  starts the app instead, never exits, and `up -d` parks forever with the real
  container stuck in `Created`.
- **The hook still inherits the service's volumes and environment**, which is
  what makes it able to create and chown paths inside them.

Containers keep running as root where the image allows it; `PUID:PGID` is for
the human on the host, so the media tree is readable and writable from a shell
without `sudo`. Set them to your own account (`id -u`, `id -g`).

## First-run setup

Fresh installs only. Prowlarr then pushes indexers to Sonarr and Radarr for you.

**SABnzbd** — provider details → Test Server → set Username/Password under
Security → Folders: temporary folder `/data/usenet/incomplete`, completed folder
`/data/usenet/complete` → Categories: default category folder `other`, add
`library` → Switches: enable Direct Unpack.

**Prowlarr** — set auth (Forms) → add indexers → Settings → Apps → add each *arr
with Full Sync, Prowlarr server `http://prowlarr:9696`, *arr server
`http://sonarr:8989` / `http://radarr:7878`, and that *arr's API key.

**Sonarr / Radarr** — add root folder `/data/media/series` and
`/data/media/movies` → quality profile → add SABnzbd as download client (host
`sabnzbd`, port 8080, its API key, category `library`) → auth (Forms).

**Bazarr** — auth (Forms) → Languages: add a profile → Providers: add one (e.g.
OpenSubtitles.com) → link Sonarr and Radarr with their API keys.

**Plex** — get a claim code from https://plex.tv/claim, put it in `PLEX_CLAIM`,
`docker compose up -d plex`, then blank it again → add libraries
(`/data/media/movies`, `/data/media/series`, `/data/media/music`) → enable
hardware transcoding under Settings → Transcoder if `/dev/dri` is uncommented.

**Seerr** — sign in with Plex → select server and libraries → add Radarr
(`radarr`, API key, quality profile, root folder) and Sonarr (`sonarr`, same
plus language and anime profiles, Season Folders) → Users: set auto-approve.

**Configarr / Decluttarr** — put `SONARR_API_KEY` and `RADARR_API_KEY` in `.env`
(each app's Settings → General → Security), then
`docker compose --profile tools up -d`. Configarr exits 0 after each run; that is
success, not a crash. Decluttarr needs ~30 min (3 strikes × 10 min) before it
removes anything; set `test_run: true` in `decluttarr/config.yaml` for a dry run.
