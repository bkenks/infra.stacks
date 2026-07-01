# stream

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs, its secret/deploy specifics, and first-run UI setup.

A self-hosted media stack — Plex + the *arr suite + download client — deployed as a single Komodo stack.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

## Services

All HTTP services are fronted by Traefik on the wildcard `*.homektb.com` cert, except Plex which keeps host networking.

| Service    | Reached at              | Internal port | Notes                                                                    |
|------------|--------------------------|----------------|---------------------------------------------------------------------------|
| Plex       | host net `:32400`        | 32400          | Media server — `network_mode: host`, **not** behind Traefik; GPU passthrough (`/dev/dri`) for hardware transcoding |
| Seer       | `seerr.homektb.com`      | 5055           | Request management (Overseerr's successor); runs as `node`, `init: true`, no container healthcheck (image ships no curl/wget/bash) |
| Prowlarr   | `prowlarr.homektb.com`   | 9696           | Indexer aggregator                                                       |
| Radarr     | `radarr.homektb.com`     | 7878           | Movies                                                                    |
| Sonarr     | `sonarr.homektb.com`     | 8989           | TV                                                                        |
| Bazarr     | `bazarr.homektb.com`     | 6767           | Subtitles                                                                 |
| SABnzbd    | `sabnzbd.homektb.com`    | 8080           | Usenet download client                                                   |
| Configarr  | — (no UI)                | —              | One-shot job: syncs TRaSH quality config (code) → Sonarr/Radarr, then exits |
| Decluttarr | — (no UI)                | —              | Long-running: clears failed/stalled/orphaned downloads from the queues   |

Configarr and Decluttarr sit on the `default` network only (no Traefik) — they reach `sonarr:8989` / `radarr:7878` by service name. The other six services join `default` **and** the external `shared-proxy` network.

## Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/stream` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.stream`), `prod` environment:
  - `SONARR_API_KEY` — Sonarr → Settings → General → Security → API Key.
  - `RADARR_API_KEY` — Radarr → Settings → General → Security → API Key.
- The agent renders them to `/dev/shm/stream.env` on the **same host**; `compose.jsonnet`'s `include.env_file` pulls it in.
- Both keys are consumed by **Configarr** (`!env` in `configarr/config.yml`) and **Decluttarr** (`!ENV` in `decluttarr/config.yaml`) — inlined as `${SONARR_API_KEY:?err}` / `${RADARR_API_KEY:?err}` in each service's `environment:` block in `compose.stack.jsonnet`. The stack fails closed if `/dev/shm/stream.env` is missing.
- Plex's `PLEX_CLAIM` (first-claim only, see below) is the one exception — a short-lived value set manually via the host/Komodo env, not rendered via Infisical.

Non-secret config (PUID/PGID/TZ per service, restart counts, image tags/digests, ports) is baked directly into `compose.stack.jsonnet`'s per-service `environment:` blocks — no `.env` files for it.

## Bind mounts

No named Docker volumes in this stack — everything is a host bind mount under `lib.registry.dockerVolumes` (`/srv/docker/bind-mounts`), baked into `compose.stack.jsonnet` at compile time. **No volume-rename step is needed** for this migration.

Expected host layout under `${DOCKER_VOLUMES}/stream/`:

```
stream/
├── bazarr/config
├── configarr/repos          # writable cache — Configarr clones the TRaSH-guide repo here
├── plex/config
├── prowlarr/config
├── radarr/config
├── sabnzbd/config
├── seerr/config
├── sonarr/config
└── shared/
    ├── media/
    │   ├── movies
    │   └── series
    └── usenet/
        ├── incomplete
        └── complete/
            ├── series
            └── movies
```

`bazarr`, `radarr`, `sabnzbd`, and `sonarr` all mount the same `stream/shared` tree at `/data` (TRaSH single-mount layout, so imports hardlink instead of copy — do not add nested submounts). Plex mounts only `stream/shared/media` at `/data/media`.

Configarr's and Decluttarr's actual *config* — `configarr/config.yml` / `decluttarr/config.yaml` — lives in this repo and is bind-mounted read-only (`./configarr:/app/config:ro`, `./decluttarr:/app/config:ro`); it is **not** host state. Only Configarr's TRaSH-guide clone cache (`stream/configarr/repos`) needs to exist on the host and be writable.

## Notes / quirks

- **Restart policy is `on-failure:5`** for every service. Komodo manages lifecycle; `on-failure` does **not** auto-start on host reboot.
- **Healthchecks use `curl`** (present in the linuxserver images). Seer ships no curl/wget/bash, so it has no container healthcheck.
- **Configarr is a one-shot job.** It runs on deploy, applies `configarr/config.yml`, and exits 0 — so it shows as **exited** in Komodo, which is normal, not a failure. It `depends_on` Sonarr + Radarr being healthy. Re-apply by redeploying the stack or restarting just the `configarr` service.
- **Decluttarr is long-running** (unlike Configarr). It loops every `timer` minutes (10) and removes failed/stalled/slow/orphaned downloads from the Sonarr/Radarr queues, blocklists them, and re-searches. A download must be flagged on `max_strikes` (3) consecutive scans before removal (≈30 min). It `depends_on` Sonarr + Radarr healthy and reads the same `SONARR_API_KEY`/`RADARR_API_KEY` as Configarr. Tune jobs/timers in `decluttarr/config.yaml`; set `test_run: true` there for a dry-run.
- **Prowlarr/Radarr/SABnzbd/Sonarr are pinned by digest** (`@sha256:...`), not tag, for reproducibility. Plex/Seer/Bazarr/Configarr/Decluttarr are pinned by version tag.
- **Seer (Overseerr's successor).** Migrated from `sctx/overseerr` to `ghcr.io/seerr-team/seerr`; the existing `/app/config` DB auto-migrates in place on first boot (same port 5055). Seer runs as the non-root `node` user (UID 1000), so it needs `init: true` **and** the host config dir owned `1000:1000`.

## Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```

## First-run service setup

The steps below are for a **fresh** install of each app. Once set up, Prowlarr pushes indexers to Sonarr/Radarr automatically and nothing here needs repeating.

### 1. SABnzbd

Access SABnzbd at `sabnzbd.homektb.com`.

1. Configure the fields according to what your Usenet provider gives you.
2. Click Test Server to make sure you entered the fields correctly, click Next, click Go to SABnzbd, click the top-right gear icon, click General.
3. Under Security, set a SABnzbd Username and Password and click Save Changes, click OK in the popup and wait for the restart to complete. Login and go to the settings again.
   - If SABnzbd fails to restart automatically, restart it manually: `docker compose restart sabnzbd`.
4. Go to the Folders tab and configure the Completed Download Folder to `/data/usenet`, save changes.
5. Go to the Categories tab and remove all the default categories using the trash bin icons. Configure the default category's Folder/Path to `other`, save. Add a new category named `library` with Folder/Path set to `library`, click Add.
6. Go to the Switches tab and tick Direct Unpack under Queue, save.

### 2. *ARRs

Access each *arr at its `<service>.homektb.com` hostname.

#### Prowlarr

1. Select Forms (Login Page), set a Username and Password and click Save.
2. Click Add indexer on the top panel, search for the Usenet/torrent indexers you want, fill the required fields, Test then Save.
3. Settings → UI → adjust date formats if desired, Save.
4. Settings → Apps → `+`.

> **This is the step that makes Prowlarr worth running.** Wiring an *arr as an "App" here means Prowlarr **pushes every indexer (and any future indexer change) to that *arr automatically** — you configure indexers once, in Prowlarr, instead of per-app.
>
> **Use internal container DNS, not a server IP.** All these services share the `default` compose network, so they resolve each other by service name:
>
> | Field           | Value                   |
> |-----------------|--------------------------|
> | Prowlarr Server | `http://prowlarr:9696`  |
> | Sonarr Server   | `http://sonarr:8989`    |
> | Radarr Server   | `http://radarr:7878`    |

**For each *arr app in Prowlarr:**

1. Set Sync Level to Full Sync.
2. Prowlarr Server field: `http://prowlarr:9696`.
3. *arr Server field: `http://sonarr:8989` for Sonarr, `http://radarr:7878` for Radarr.
4. In the *arr app: Settings → General → copy the API Key under Security. Paste into the ApiKey field, Save.

#### Bazarr

Access Bazarr at `bazarr.homektb.com`.

- **General** — Settings → General → Authentication: Form, set Username/Password, Save.
- **Languages** — Settings → Languages → pick language(s), Add New Profile, name it `Main`, add languages, Save.
- **Providers** — Settings → Providers → `+` → add each provider (OpenSubtitles.com recommended) with its credentials, Save.
- **Sonarr/Radarr link** — Settings → Sonarr → enable, Address = internal service name (or `sonarr.homektb.com` / port 443 with SSL if using the public hostname), paste the Sonarr API Key, Test, Save. Repeat under Settings → Radarr.

#### Other *arr apps (Sonarr, Radarr)

Access each at its `<service>.homektb.com` hostname.

- **Language** (Sonarr/Radarr) — Settings → Profiles → Language Profiles → add languages as needed, name `Main`, Save.
- **Quality** (Sonarr/Radarr) — Settings → Quality → Hide Advanced → cap max size per quality tier as desired (e.g. ~4.7 GB/hr for 1080p). Radarr also needs a Preferred value. Save.
- **SABnzbd download client** — add SABnzbd, Host = `sabnzbd` (internal DNS) or `sabnzbd.homektb.com`, Port 8080, API Key from SABnzbd's General settings, same Username/Password as SABnzbd, Category = `library`, Save.
- **General** — Settings → UI → adjust Calendar/Dates formats if desired. Settings → General → Authentication: Form, set Username/Password, Save (restart if prompted).

#### Configarr (quality profiles + custom formats as code)

Configarr replaces manual Quality tuning with config-as-code. One-shot container: on every stack deploy it reads [`configarr/config.yml`](./configarr/config.yml) and syncs the declared [TRaSH-guide](https://trash-guides.info) quality definitions, quality profiles, and custom formats into Sonarr and Radarr, then exits. It only manages **quality scoring** — not indexers (Prowlarr), download clients, root folders, or media.

Runs automatically as part of `Deploy` in Komodo. After a successful run it shows as **exited (0)** — expected, not a failure. To re-apply after editing the config, redeploy the stack (or restart just `configarr`). Check its container logs to see what it changed.

Edit [`configarr/config.yml`](./configarr/config.yml), commit, redeploy. Ships with the TRaSH **1080p WEB** profile for Sonarr and **HD Bluray + WEB** for Radarr; comments in the file show how to switch to 4K/2160p. Template names come from the [recyclarr template list](https://recyclarr.dev/wiki/) (Configarr uses the same set).

### 3. Plex

1. Stop the `plex` container.
2. Go to plex.tv/claim, copy the code, set it as `PLEX_CLAIM` via the host/Komodo env (short-lived, one-time — not committed to this repo).
3. Restart the container.
4. Access Plex at `<host-ip>:32400` (host networking — not behind Traefik).
5. Log in with your Plex account.
6. Click GOT IT!, close the popup, name your library.
7. Add Library → Movies → Next → Browse for Media Folder → `/data/media/movies` → Add Library.
8. Add Library → TV Shows → name it `Series` → Next → Browse for Media Folder → `/data/media/series` → Add Library.
9. Add Library → TV Shows → name it `Music` → Next → Browse for Media Folder → `/data/media/music` → Add Library.
10. Next → Done.
11. Top-right wrench icon → Settings → Library → tick "Scan my library automatically" and "Run a partial scan when changes are detected"; set thumbnail generation to scheduled + on-add. Save Changes.
12. Settings → Plex Web → Quality → set a default streaming quality.
13. For remote access: allow port 32400 in your firewall/router, Settings → Remote Access → "Manually specify public port" → 32400 → Apply.
14. Enable hardware acceleration/transcoding in Settings → Transcoder (uses the passed-through `/dev/dri` device).

### 4. Seer

> Migrated from Overseerr — an existing config/database carries over automatically on first boot. The steps below are for a **fresh** install. UI is reached at `seerr.homektb.com`.

1. Access Seer at `seerr.homektb.com`.
2. Sign in with Plex.
3. Click the refresh icon, wait, select the Plex server entry (prioritize [secure] then [local]). Save changes, select Movies and Series, Continue.
   - **Radarr** — Add Radarr Server, tick Default server, name it `Radarr`, Hostname/IP = `radarr` (internal DNS). Paste the Radarr API Key (Radarr → Settings → General → Security). Test, select quality profile + root folder, Enable Scan, Add Server.
   - **Sonarr** — repeat with `sonarr`, plus select language profile, anime quality profile, anime language profile, and tick Season Folders.
4. Click Finish Setup.
5. Settings → Users tab → tick Auto-Approve and Auto-Request → Save Changes.
