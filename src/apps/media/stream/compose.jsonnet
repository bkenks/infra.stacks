// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML. All storage is host
// bind mounts — no named Docker volumes in this stack, so no volume-rename
// step on first deploy.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;

local name = 'stream';
local bindRoot = reg.dirs.docker.root + reg.dirs.docker.bindMounts;

// Service keys are app names, not roles from reg.role — nothing here is a generic
// app/db/worker. Bound as locals so the depends_on references below fail at compile
// time on a typo instead of silently waiting on a service that does not exist.
local bazarr = 'bazarr';
local configarr = 'configarr';
local decluttarr = 'decluttarr';
local plex = 'plex';
local prowlarr = 'prowlarr';
local radarr = 'radarr';
local sabnzbd = 'sabnzbd';
local seerr = 'seerr';
local sonarr = 'sonarr';

local tz = 'America/New_York';
local puid = 1000;
local pgid = 1000;
local maxRestart = 5;
local restart = 'on-failure:' + std.toString(maxRestart);

// The linuxserver.io images drop to this uid/gid; the bind mounts under bindRoot are
// owned by it. plex and seerr opt out — see their notes.
local lsioEnv = { PUID: std.toString(puid), PGID: std.toString(pgid), TZ: tz };

// Shared TRaSH-layout data mount so the *arr apps hardlink imports instead of
// copying (downloads + library on one device). Do NOT add nested submounts.
local sharedData = bindRoot + '/stream/shared';

local versions = {
  bazarr: '1.5.4',
  configarr: '1.28.0',
  decluttarr: 'v2.1.0',
  plex: '1.43.3',
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

// Every one of these images ships curl and answers on loopback, so the six healthchecks
// differ only in port and path.
local httpHealth(port, path) = {
  test: ['CMD-SHELL', 'curl -fsS http://localhost:%d%s || exit 1' % [port, path]],
  interval: '30s',
  timeout: '10s',
  retries: 5,
  start_period: '30s',
};

// configarr and decluttarr both drive the *arr APIs, so both wait for them to be healthy
// rather than merely started.
local arrsHealthy = {
  [radarr]: { condition: 'service_healthy' },
  [sonarr]: { condition: 'service_healthy' },
};

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [bazarr]: lib.Service {
      image: 'lscr.io/linuxserver/bazarr:' + versions.bazarr,
      mounts_:: [
        bindRoot + '/stream/bazarr/config:/config',
        sharedData + ':/data',
      ],
      environment: lsioEnv,
      restart: restart,
      healthcheck: httpHealth(ports.bazarr, '/'),
      expose: [std.toString(ports.bazarr)],
      ports: ['%s:6767:%d' % [reg.ips.loopback, ports.bazarr]],
    },

    // One-shot: syncs ./configarr/config.yml into Sonarr/Radarr on each
    // deploy, then exits 0.
    [configarr]: lib.Service {
      image: 'ghcr.io/raydak-labs/configarr:' + versions.configarr,
      depends_on: arrsHealthy,
      mounts_:: [
        './configarr:/app/config:ro',
        bindRoot + '/stream/configarr/repos:/app/repos',
      ],
      environment: lsioEnv {
        // Read via `!env` in ./configarr/config.yml.
        SONARR_API_KEY: '${SONARR_API_KEY:?err}',
        RADARR_API_KEY: '${RADARR_API_KEY:?err}',
      },
      restart: restart,
    },

    // Long-running: every `timer` minutes scans the Sonarr/Radarr queues,
    // removes failed/stalled/slow/orphaned downloads, and triggers a re-search.
    [decluttarr]: lib.Service {
      image: 'ghcr.io/manimatter/decluttarr:' + versions.decluttarr,
      depends_on: arrsHealthy,
      mounts_:: ['./decluttarr:/app/config:ro'],
      environment: lsioEnv {
        // Read via `!ENV` in ./decluttarr/config.yaml.
        SONARR_API_KEY: '${SONARR_API_KEY:?err}',
        RADARR_API_KEY: '${RADARR_API_KEY:?err}',
      },
      restart: restart,
    },

    // network_mode: host (NOT Traefik-fronted); GPU passthrough (Intel iGPU)
    // for hardware transcoding. Runs as root (PUID/PGID 0), so no group_add
    // for render is needed.
    [plex]: lib.Service {
      image: 'lscr.io/linuxserver/plex:' + versions.plex,
      mounts_:: [
        bindRoot + '/stream/plex/config:/config',
        bindRoot + '/stream/shared/media:/data/media',
      ],
      environment: {
        PUID: '0',
        PGID: '0',
        TZ: tz,
        PLEX_CLAIM: '${PLEX_CLAIM:-}',  // optional, only needed on fresh start
        // "docker" = pinned-by-image, no in-container update.
        VERSION: 'docker',
      },
      devices: ['/dev/dri:/dev/dri'],
      network_mode: 'host',
      // Compose rejects network_mode and networks on the same service, so the alias block
      // the Service base sets has to go. null is pruned out of the rendered manifest.
      networks: null,
      restart: restart,
      healthcheck: httpHealth(ports.plex, '/identity'),
    },

    [prowlarr]: lib.Service {
      image: 'lscr.io/linuxserver/prowlarr@sha256:d3e9307b320b6772749a2cf8fc2712e9e824c4930b034680ad4d08a9e2f25884',
      mounts_:: [bindRoot + '/stream/prowlarr/config:/config'],
      environment: lsioEnv,
      restart: restart,
      healthcheck: httpHealth(ports.prowlarr, '/ping'),
      expose: [std.toString(ports.prowlarr)],
      ports: ['%s:9696:%d' % [reg.ips.loopback, ports.prowlarr]],
    },

    [radarr]: lib.Service {
      image: 'lscr.io/linuxserver/radarr@sha256:270f25698624b57b86ca119cc95399d7ff15be8297095b4e1223fd5b549b732c',
      mounts_:: [
        bindRoot + '/stream/radarr/config:/config',
        sharedData + ':/data',
      ],
      environment: lsioEnv,
      restart: restart,
      healthcheck: httpHealth(ports.radarr, '/ping'),
      expose: [std.toString(ports.radarr)],
      ports: ['%s:7878:%d' % [reg.ips.loopback, ports.radarr]],
    },

    [sabnzbd]: lib.Service {
      image: 'lscr.io/linuxserver/sabnzbd@sha256:fba727f777f6b2633fcdeaea94abc85d73148f2a6b19a8158907bdd5b6e145d0',
      mounts_:: [
        bindRoot + '/stream/sabnzbd/config:/config',
        sharedData + ':/data',
      ],
      environment: lsioEnv,
      restart: restart,
      healthcheck: httpHealth(ports.sabnzbd, '/'),
      expose: [std.toString(ports.sabnzbd)],
      ports: ['%s:18013:%d' % [reg.ips.loopback, ports.sabnzbd]],
    },

    // Runs as the fixed non-root `node` user (UID 1000) — PUID/PGID have no
    // effect; needs `init: true`. No healthcheck: image ships no curl/wget/bash.
    [seerr]: lib.Service {
      image: 'ghcr.io/seerr-team/seerr:' + versions.seerr,
      mounts_:: [bindRoot + '/stream/seerr/config:/app/config'],
      environment: { TZ: tz },
      restart: restart,
      expose: [std.toString(ports.seerr)],
      ports: ['%s:5055:%d' % [reg.ips.loopback, ports.seerr]],
      init: true,
    },

    [sonarr]: lib.Service {
      image: 'lscr.io/linuxserver/sonarr@sha256:02b4d538d351d6e35882a021c08e8600fe95d28860fb1dd724b597166e7221ca',
      mounts_:: [
        bindRoot + '/stream/sonarr/config:/config',
        sharedData + ':/data',
      ],
      environment: lsioEnv,
      restart: restart,
      healthcheck: httpHealth(ports.sonarr, '/ping'),
      expose: [std.toString(ports.sonarr)],
      ports: ['%s:8989:%d' % [reg.ips.loopback, ports.sonarr]],
    },
  }),
  [lib.Secret('stream')],
)
