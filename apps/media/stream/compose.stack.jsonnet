// stream — Plex + the *arr suite + download client (self-hosted media stack).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. bazarr/prowlarr/radarr/sabnzbd/seerr/sonarr join shared-proxy (traefik
// owns) to be reachable; configarr/decluttarr stay on `default` only (no UI);
// plex uses network_mode: host (no networks block at all) with GPU passthrough
// for hardware transcoding.
//
// All storage is host bind mounts under lib.registry.dockerVolumes — no named
// Docker volumes in this stack, so no volume-rename step on first deploy.
local lib = import 'lib.libsonnet';

local stack = 'stream';
local n = lib.compose.names(stack);
local dv = lib.registry.dockerVolumes;

local tz = 'America/New_York';
local puid = 1000;
local pgid = 1000;
local maxRestart = 5;
local restart = 'on-failure:' + std.toString(maxRestart);

// Shared TRaSH-layout data mount (downloads + library on one device, so the
// *arr apps hardlink imports instead of copying). Do NOT add nested submounts.
local sharedData = dv + '/stream/shared';

local versions = {
  bazarr: '1.5.4',           // lscr.io/linuxserver/bazarr
  configarr: '1.28.0',       // ghcr.io/raydak-labs/configarr
  decluttarr: 'v2.1.0',      // ghcr.io/manimatter/decluttarr
  plex: '1.43.2',            // lscr.io/linuxserver/plex
  seerr: 'v3.0.1',           // ghcr.io/seerr-team/seerr
};

local ports = {
  bazarr: 6767,
  plex: 32400,
  prowlarr: 9696,
  radarr: 7878,
  sabnzbd: 8080,
  seerr: 5055,
  sonarr: 8989,
};

{
  name: stack,

  services: {
    bazarr: {
      image: 'lscr.io/linuxserver/bazarr:' + versions.bazarr,
      container_name: n.container('bazarr'),
      volumes: [
        dv + '/stream/bazarr/config:/config',
        sharedData + ':/data',
      ],
      environment: { PUID: std.toString(puid), PGID: std.toString(pgid), TZ: tz },
      restart: restart,
      healthcheck: {
        test: ['CMD-SHELL', 'curl -fsS http://localhost:' + std.toString(ports.bazarr) + '/ || exit 1'],
        interval: '30s',
        timeout: '10s',
        retries: 5,
        start_period: '30s',
      },
      expose: [std.toString(ports.bazarr)],
      networks: {
        default: { aliases: [n.alias('bazarr')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('bazarr')] },
      },
      labels: lib.mixins.proxyAdd('bazarr', 'bazarr', ports.bazarr),
    },

    // Configarr (config-as-code for Sonarr/Radarr quality) — one-shot job:
    // syncs ./configarr/config.yml (TRaSH quality profiles + custom formats)
    // into Sonarr & Radarr on each deploy, then exits 0. No web UI / no
    // Traefik — only needs `default` to reach sonarr:8989 / radarr:7878.
    configarr: {
      image: 'ghcr.io/raydak-labs/configarr:' + versions.configarr,
      container_name: n.container('configarr'),
      depends_on: {
        radarr: { condition: 'service_healthy' },
        sonarr: { condition: 'service_healthy' },
      },
      volumes: [
        './configarr:/app/config:ro',
        dv + '/stream/configarr/repos:/app/repos',
      ],
      environment: {
        PUID: std.toString(puid),
        PGID: std.toString(pgid),
        TZ: tz,
        // Secrets — interpolated from /dev/shm/stream.env (parent include.env_file).
        // Read via `!env` in ./configarr/config.yml.
        SONARR_API_KEY: '${SONARR_API_KEY:?err}',
        RADARR_API_KEY: '${RADARR_API_KEY:?err}',
      },
      restart: restart,
      networks: { default: { aliases: [n.alias('configarr')] } },
    },

    // Decluttarr (download-queue janitor) — long-running: every `timer`
    // minutes it scans the Sonarr/Radarr queues and removes failed / stalled /
    // slow / orphaned downloads, blocklists them, and triggers a fresh search.
    // Config-as-code in ./decluttarr/config.yaml (mounted read-only). No web
    // UI / no Traefik — only needs `default` to reach sonarr:8989 / radarr:7878.
    decluttarr: {
      image: 'ghcr.io/manimatter/decluttarr:' + versions.decluttarr,
      container_name: n.container('decluttarr'),
      depends_on: {
        radarr: { condition: 'service_healthy' },
        sonarr: { condition: 'service_healthy' },
      },
      volumes: ['./decluttarr:/app/config:ro'],
      environment: {
        PUID: std.toString(puid),
        PGID: std.toString(pgid),
        TZ: tz,
        // Secrets — interpolated from /dev/shm/stream.env (parent include.env_file).
        // Read via `!ENV` in ./decluttarr/config.yaml.
        SONARR_API_KEY: '${SONARR_API_KEY:?err}',
        RADARR_API_KEY: '${RADARR_API_KEY:?err}',
      },
      restart: restart,
      networks: { default: { aliases: [n.alias('decluttarr')] } },
    },

    // Plex — network_mode: host (NOT Traefik-fronted); GPU passthrough
    // (Intel iGPU) for hardware transcoding (VAAPI/Quick Sync). Runs as root
    // (PUID/PGID 0), so no group_add for render is needed.
    plex: {
      image: 'lscr.io/linuxserver/plex:' + versions.plex,
      container_name: n.container('plex'),
      volumes: [
        dv + '/stream/plex/config:/config',
        dv + '/stream/shared/media:/data/media',
      ],
      environment: {
        PUID: '0',
        PGID: '0',
        TZ: tz,
        // linuxserver/plex update channel ("docker" = pinned-by-image, no
        // in-container update).
        VERSION: 'docker',
        // Only needed for the very first server claim (plex.tv/claim) — set
        // it via the host/Komodo env for a one-time claim, not committed here.
        // PLEX_CLAIM: '${PLEX_CLAIM:-}',
      },
      devices: ['/dev/dri:/dev/dri'],
      network_mode: 'host',
      restart: restart,
      healthcheck: {
        test: ['CMD-SHELL', 'curl -fsS http://localhost:' + std.toString(ports.plex) + '/identity || exit 1'],
        interval: '30s',
        timeout: '10s',
        retries: 5,
        start_period: '30s',
      },
    },

    prowlarr: {
      image: 'lscr.io/linuxserver/prowlarr@sha256:d3e9307b320b6772749a2cf8fc2712e9e824c4930b034680ad4d08a9e2f25884',
      container_name: n.container('prowlarr'),
      volumes: [dv + '/stream/prowlarr/config:/config'],
      environment: { PUID: std.toString(puid), PGID: std.toString(pgid), TZ: tz },
      restart: restart,
      healthcheck: {
        test: ['CMD-SHELL', 'curl -fsS http://localhost:' + std.toString(ports.prowlarr) + '/ping || exit 1'],
        interval: '30s',
        timeout: '10s',
        retries: 5,
        start_period: '30s',
      },
      expose: [std.toString(ports.prowlarr)],
      networks: {
        default: { aliases: [n.alias('prowlarr')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('prowlarr')] },
      },
      labels: lib.mixins.proxyAdd('prowlarr', 'prowlarr', ports.prowlarr),
    },

    radarr: {
      image: 'lscr.io/linuxserver/radarr@sha256:270f25698624b57b86ca119cc95399d7ff15be8297095b4e1223fd5b549b732c',
      container_name: n.container('radarr'),
      volumes: [
        dv + '/stream/radarr/config:/config',
        sharedData + ':/data',
      ],
      environment: { PUID: std.toString(puid), PGID: std.toString(pgid), TZ: tz },
      restart: restart,
      healthcheck: {
        test: ['CMD-SHELL', 'curl -fsS http://localhost:' + std.toString(ports.radarr) + '/ping || exit 1'],
        interval: '30s',
        timeout: '10s',
        retries: 5,
        start_period: '30s',
      },
      expose: [std.toString(ports.radarr)],
      networks: {
        default: { aliases: [n.alias('radarr')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('radarr')] },
      },
      labels: lib.mixins.proxyAdd('radarr', 'radarr', ports.radarr),
    },

    sabnzbd: {
      image: 'lscr.io/linuxserver/sabnzbd@sha256:fba727f777f6b2633fcdeaea94abc85d73148f2a6b19a8158907bdd5b6e145d0',
      container_name: n.container('sabnzbd'),
      volumes: [
        dv + '/stream/sabnzbd/config:/config',
        sharedData + ':/data',
      ],
      environment: { PUID: std.toString(puid), PGID: std.toString(pgid), TZ: tz },
      restart: restart,
      healthcheck: {
        test: ['CMD-SHELL', 'curl -fsS http://localhost:' + std.toString(ports.sabnzbd) + '/ || exit 1'],
        interval: '30s',
        timeout: '10s',
        retries: 5,
        start_period: '30s',
      },
      expose: [std.toString(ports.sabnzbd)],
      networks: {
        default: { aliases: [n.alias('sabnzbd')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('sabnzbd')] },
      },
      labels: lib.mixins.proxyAdd('sabnzbd', 'sabnzbd', ports.sabnzbd),
    },

    // Seer (Overseerr's successor — request management). Runs as the fixed
    // non-root `node` user (UID 1000, ignores PUID/PGID) — needs `init: true`.
    // No container healthcheck: the image ships no curl/wget/bash.
    seerr: {
      image: 'ghcr.io/seerr-team/seerr:' + versions.seerr,
      container_name: n.container('seerr'),
      volumes: [dv + '/stream/seerr/config:/app/config'],
      environment: { TZ: tz },
      restart: restart,
      expose: [std.toString(ports.seerr)],
      networks: {
        default: { aliases: [n.alias('seerr')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('seerr')] },
      },
      labels: lib.mixins.proxyAdd('seerr', 'seerr', ports.seerr),
      init: true,
    },

    sonarr: {
      image: 'lscr.io/linuxserver/sonarr@sha256:02b4d538d351d6e35882a021c08e8600fe95d28860fb1dd724b597166e7221ca',
      container_name: n.container('sonarr'),
      volumes: [
        dv + '/stream/sonarr/config:/config',
        sharedData + ':/data',
      ],
      environment: { PUID: std.toString(puid), PGID: std.toString(pgid), TZ: tz },
      restart: restart,
      healthcheck: {
        test: ['CMD-SHELL', 'curl -fsS http://localhost:' + std.toString(ports.sonarr) + '/ping || exit 1'],
        interval: '30s',
        timeout: '10s',
        retries: 5,
        start_period: '30s',
      },
      expose: [std.toString(ports.sonarr)],
      networks: {
        default: { aliases: [n.alias('sonarr')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('sonarr')] },
      },
      labels: lib.mixins.proxyAdd('sonarr', 'sonarr', ports.sonarr),
    },
  },

  networks:
    n.network
    + lib.compose.join('proxy'),
}
