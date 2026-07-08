// Compiles to compose.stack.yaml — do not edit the YAML. All storage is host
// bind mounts — no named Docker volumes in this stack, so no volume-rename
// step on first deploy.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'stream';
local s = c.stack(stack);
local n = s.names;
local dv = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts;

local tz = 'America/New_York';
local puid = 1000;
local pgid = 1000;
local maxRestart = 5;
local restart = 'on-failure:' + std.toString(maxRestart);

// Shared TRaSH-layout data mount so the *arr apps hardlink imports instead of
// copying (downloads + library on one device). Do NOT add nested submounts.
local sharedData = dv + '/stream/shared';

local versions = {
  bazarr: '1.5.4',
  configarr: '1.28.0',
  decluttarr: 'v2.1.0',
  plex: '1.43.2',
  seerr: 'v3.0.1',
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
        default: { aliases: [n.container('bazarr')] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container('bazarr')] },
      },
      labels: s.proxy.add('bazarr', 'bazarr', ports.bazarr),
    },

    // One-shot: syncs ./configarr/config.yml into Sonarr/Radarr on each
    // deploy, then exits 0.
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
        // Read via `!env` in ./configarr/config.yml.
        SONARR_API_KEY: '${SONARR_API_KEY:?err}',
        RADARR_API_KEY: '${RADARR_API_KEY:?err}',
      },
      restart: restart,
      networks: { default: { aliases: [n.container('configarr')] } },
    },

    // Long-running: every `timer` minutes scans the Sonarr/Radarr queues,
    // removes failed/stalled/slow/orphaned downloads, and triggers a re-search.
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
        // Read via `!ENV` in ./decluttarr/config.yaml.
        SONARR_API_KEY: '${SONARR_API_KEY:?err}',
        RADARR_API_KEY: '${RADARR_API_KEY:?err}',
      },
      restart: restart,
      networks: { default: { aliases: [n.container('decluttarr')] } },
    },

    // network_mode: host (NOT Traefik-fronted); GPU passthrough (Intel iGPU)
    // for hardware transcoding. Runs as root (PUID/PGID 0), so no group_add
    // for render is needed.
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
        // "docker" = pinned-by-image, no in-container update.
        VERSION: 'docker',
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
        default: { aliases: [n.container('prowlarr')] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container('prowlarr')] },
      },
      labels: s.proxy.add('prowlarr', 'prowlarr', ports.prowlarr),
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
        default: { aliases: [n.container('radarr')] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container('radarr')] },
      },
      labels: s.proxy.add('radarr', 'radarr', ports.radarr),
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
        default: { aliases: [n.container('sabnzbd')] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container('sabnzbd')] },
      },
      labels: s.proxy.add('sabnzbd', 'sabnzbd', ports.sabnzbd),
    },

    // Runs as the fixed non-root `node` user (UID 1000) — PUID/PGID have no
    // effect; needs `init: true`. No healthcheck: image ships no curl/wget/bash.
    seerr: {
      image: 'ghcr.io/seerr-team/seerr:' + versions.seerr,
      container_name: n.container('seerr'),
      volumes: [dv + '/stream/seerr/config:/app/config'],
      environment: { TZ: tz },
      restart: restart,
      expose: [std.toString(ports.seerr)],
      networks: {
        default: { aliases: [n.container('seerr')] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container('seerr')] },
      },
      labels: s.proxy.add('seerr', 'seerr', ports.seerr),
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
        default: { aliases: [n.container('sonarr')] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container('sonarr')] },
      },
      labels: s.proxy.add('sonarr', 'sonarr', ports.sonarr),
    },
  },

  networks:
    s.network.default
    + s.network.join('proxy'),
}
