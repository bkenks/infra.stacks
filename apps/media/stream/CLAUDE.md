# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A self-hosted media streaming stack (Plex + the *arr suite + download client),
deployed as a **single Komodo stack** following the `template.stack` convention.
The operational/architecture source of truth is Notion; this repo is the source
of truth for compose/usage. Per-app first-run UI setup lives in `README.md`; the
stack's deploy specifics live in `setup.md`.

## Services and Ports

| Service   | Internal port | Reached at                | Purpose                          |
|-----------|---------------|---------------------------|----------------------------------|
| Plex      | 32400         | host net `:32400`             | Media server (`network_mode: host`, **not** Traefik) |
| Seer      | 5055          | `seerr.paiki.homektb.com`     | Request management (Overseerr successor; runs as `node`, `init: true`) |
| Prowlarr  | 9696          | `prowlarr.paiki.homektb.com`  | Indexer aggregator               |
| Radarr    | 7878          | `radarr.paiki.homektb.com`    | Movies                           |
| Sonarr    | 8989          | `sonarr.paiki.homektb.com`    | TV                               |
| Bazarr    | 6767          | `bazarr.paiki.homektb.com`    | Subtitles                        |
| SABnzbd   | 8080          | `sabnzbd.paiki.homektb.com`   | Usenet download client           |
| Configarr | — (no UI)     | —                             | One-shot: syncs TRaSH quality config → Sonarr/Radarr, then exits |
| Decluttarr| — (no UI)     | —                             | Long-running: clears failed/stalled/orphaned downloads from the queues |

## Layout (template.stack convention)

```
compose.yaml                 include → compose/stack.yaml + compose/secrets.yaml ; env_file main.env + /dev/shm/stream.env
compose/stack.yaml           all 9 services + Traefik labels + bind mounts
compose/secrets.yaml         interpolated secrets (Configarr + Decluttarr SONARR/RADARR_API_KEY)
container-envs/<svc>.env      per-service LITERAL env (PUID/PGID/TZ; plex: VERSION)
interpolation-envs/main.env   ${...} interpolation only: names, image pins, restart counts, DOCKER_VOLUMES
configarr/config.yml          config-as-code: TRaSH quality profiles + custom formats (read-only into Configarr)
decluttarr/config.yaml        config-as-code: queue-cleanup jobs + Sonarr/Radarr instances (read-only into Decluttarr)
setup.md                     deploy specifics (this stack)
README.md                    per-app first-run UI walkthrough
```

The split exists because a service's `env_file:` is **not** interpolated, so any
`${...}` only resolves in the compose body. Literal container env →
`container-envs/<svc>.env`; anything with `${...}` → `interpolation-envs/main.env`
(or `compose/secrets.yaml` for the rendered API keys).

## Networking

The six HTTP services sit on the compose `default` network (so they resolve each
other by service name, e.g. Prowlarr → `http://sonarr:8989`) **and** the external
`proxy` network (so the per-host Traefik edge stack can route to them). Traefik
labels (`Host(\`<svc>.homektb.com\`)`, websecure, tls) live on each. Plex is
`network_mode: host`; other services reach it via the host IP.

## Environment / required host config

- **`DOCKER_VOLUMES`** — base path for the bind-mounted data. **Required, no
  default** (a wrong value mounts empty dirs and apps re-initialise with lost
  state). Set in `interpolation-envs/main.env` or the host/Komodo env. Must
  already contain `stream/{plex,sonarr,…}/config` and `stream/shared/{media,usenet}`.
- **`PLEX_CLAIM`** — only for the first Plex claim; left commented in
  `container-envs/plex.env`.
- Images are pinned by version tag (Plex, Seer, Bazarr) or SHA256 digest
  (Prowlarr, SABnzbd, Radarr, Sonarr) — all in `interpolation-envs/main.env`.
- **Rendered secrets:** the Sonarr + Radarr API keys live in Infisical (`/stream`
  folder, `prod`), are rendered to `/dev/shm/stream.env` by the host's
  infisical-agent (template in `stack.node`, `paiki.yaml`), and feed
  `compose/secrets.yaml` (`${SONARR_API_KEY:?err}` / `${RADARR_API_KEY:?err}`) —
  consumed by Configarr (`!env`) and Decluttarr (`!ENV`). The stream redeploy
  **fails closed** if that file is missing. Plex's `PLEX_CLAIM` is the one
  exception (commented literal, not via Infisical).
- `restart: on-failure:N` per the template convention (not `unless-stopped`);
  Komodo manages lifecycle.

## Linting

```bash
./lint.sh
```

Runs `dclint --fix` on the YAML using `.dclintrc` (disabled rules:
`no-unbound-port-interfaces`, `require-project-name-field`).
