local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'stream',
  envFiles:: [lib.Secret('stream')],

  // Service keys are app names, not roles from lib.collections.role — nothing here is a generic
  // app/db/worker. All storage is host bind mounts, so this stack owns no volumes.
  bazarr:: self.Service { role:: 'bazarr' },
  configarr:: self.Service { role:: 'configarr' },
  decluttarr:: self.Service { role:: 'decluttarr' },
  plex:: self.Service { role:: 'plex' },
  prowlarr:: self.Service { role:: 'prowlarr' },
  radarr:: self.Service { role:: 'radarr' },
  sabnzbd:: self.Service { role:: 'sabnzbd' },
  seerr:: self.Service { role:: 'seerr' },
  sonarr:: self.Service { role:: 'sonarr' },
};

local tz = 'America/New_York';
local restart = lib.collections.restart.onFailure(5);
local bindRoot = lib.collections.dirs.docker.bindMounts + '/stream';

// The linuxserver.io images drop to this uid/gid; the bind mounts under bindRoot are owned
// by it. plex and seerr opt out — see their notes.
local lsioEnv = { PUID: '1000', PGID: '1000', TZ: tz };

// Shared TRaSH-layout data mount so the *arr apps hardlink imports instead of copying
// (downloads + library on one device). Do NOT add nested submounts.
local sharedData = bindRoot + '/shared';

local versions = {
  bazarr: '1.5.4',
  configarr: '1.28.0',
  decluttarr: 'v2.1.0',
  plex: '1.43.3',
  seerr: 'v3.0.1',
};

local ports = {
  bazarr: '6767',
  plex: '32400',
  prowlarr: '9696',
  radarr: '7878',
  sabnzbd: '8080',
  seerr: '5055',
  sonarr: '8989',
};

// Every one of these images ships curl and answers on loopback, so the six healthchecks
// differ only in port and path.
local httpHealth(port, path) = {
  test: ['CMD-SHELL', 'curl -fsS http://localhost:%s%s || exit 1' % [port, path]],
  interval: '30s',
  timeout: '10s',
  retries: 5,
  start_period: '30s',
};

// configarr and decluttarr both drive the *arr APIs, so both wait for them to be healthy
// rather than merely started.
local arrsHealthy = {
  [refs.radarr.key]: { condition: lib.collections.condition.healthy },
  [refs.sonarr.key]: { condition: lib.collections.condition.healthy },
};

// Read via `!env` / `!ENV` in the mounted config files.
local arrApiKeys = {
  SONARR_API_KEY: '${SONARR_API_KEY:?err}',
  RADARR_API_KEY: '${RADARR_API_KEY:?err}',
};

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [refs.bazarr.key]: {
        container_name: refs.bazarr.ext,
        image: 'lscr.io/linuxserver/bazarr:' + versions.bazarr,
        restart: restart,
        volumes: [
          bindRoot + '/bazarr/config:/config',
          sharedData + ':/data',
        ],
        environment: lsioEnv,
        healthcheck: httpHealth(ports.bazarr, '/'),
        expose: [ports.bazarr],
        ports: ['%s:6767:%s' % [lib.collections.ip.loopback, ports.bazarr]],
      },

      // One-shot: syncs ./configarr/config.yml into Sonarr/Radarr on each deploy, then exits 0.
      [refs.configarr.key]: {
        container_name: refs.configarr.ext,
        image: 'ghcr.io/raydak-labs/configarr:' + versions.configarr,
        restart: restart,
        depends_on: arrsHealthy,
        volumes: [
          './configarr:/app/config:ro',
          bindRoot + '/configarr/repos:/app/repos',
        ],
        environment: lsioEnv + arrApiKeys,
      },

      // Long-running: every `timer` minutes scans the Sonarr/Radarr queues, removes
      // failed/stalled/slow/orphaned downloads, and triggers a re-search.
      [refs.decluttarr.key]: {
        container_name: refs.decluttarr.ext,
        image: 'ghcr.io/manimatter/decluttarr:' + versions.decluttarr,
        restart: restart,
        depends_on: arrsHealthy,
        volumes: ['./decluttarr:/app/config:ro'],
        environment: lsioEnv + arrApiKeys,
      },

      // network_mode: host (NOT Traefik-fronted); GPU passthrough (Intel iGPU) for hardware
      // transcoding. Runs as root (PUID/PGID 0), so no group_add for render is needed.
      // Compose rejects network_mode and networks on the same service, so this one declares
      // no networks at all.
      [refs.plex.key]: {
        container_name: refs.plex.ext,
        image: 'lscr.io/linuxserver/plex:' + versions.plex,
        restart: restart,
        network_mode: 'host',
        volumes: [
          bindRoot + '/plex/config:/config',
          sharedData + '/media:/data/media',
        ],
        environment: {
          PUID: '0',
          PGID: '0',
          TZ: tz,
          // Optional, only needed on a fresh start.
          PLEX_CLAIM: '${PLEX_CLAIM:-}',
          // "docker" = pinned-by-image, no in-container update.
          VERSION: 'docker',
        },
        devices: ['/dev/dri:/dev/dri'],
        healthcheck: httpHealth(ports.plex, '/identity'),
      },

      [refs.prowlarr.key]: {
        container_name: refs.prowlarr.ext,
        image: 'lscr.io/linuxserver/prowlarr@sha256:d3e9307b320b6772749a2cf8fc2712e9e824c4930b034680ad4d08a9e2f25884',
        restart: restart,
        volumes: [bindRoot + '/prowlarr/config:/config'],
        environment: lsioEnv,
        healthcheck: httpHealth(ports.prowlarr, '/ping'),
        expose: [ports.prowlarr],
        ports: ['%s:9696:%s' % [lib.collections.ip.loopback, ports.prowlarr]],
      },

      [refs.radarr.key]: {
        container_name: refs.radarr.ext,
        image: 'lscr.io/linuxserver/radarr@sha256:270f25698624b57b86ca119cc95399d7ff15be8297095b4e1223fd5b549b732c',
        restart: restart,
        volumes: [
          bindRoot + '/radarr/config:/config',
          sharedData + ':/data',
        ],
        environment: lsioEnv,
        healthcheck: httpHealth(ports.radarr, '/ping'),
        expose: [ports.radarr],
        ports: ['%s:7878:%s' % [lib.collections.ip.loopback, ports.radarr]],
      },

      [refs.sabnzbd.key]: {
        container_name: refs.sabnzbd.ext,
        image: 'lscr.io/linuxserver/sabnzbd@sha256:fba727f777f6b2633fcdeaea94abc85d73148f2a6b19a8158907bdd5b6e145d0',
        restart: restart,
        volumes: [
          bindRoot + '/sabnzbd/config:/config',
          sharedData + ':/data',
        ],
        environment: lsioEnv,
        healthcheck: httpHealth(ports.sabnzbd, '/'),
        expose: [ports.sabnzbd],
        ports: ['%s:18013:%s' % [lib.collections.ip.loopback, ports.sabnzbd]],
      },

      // Runs as the fixed non-root `node` user (UID 1000) — PUID/PGID have no effect; needs
      // `init: true`. No healthcheck: the image ships no curl/wget/bash.
      [refs.seerr.key]: {
        container_name: refs.seerr.ext,
        image: 'ghcr.io/seerr-team/seerr:' + versions.seerr,
        restart: restart,
        volumes: [bindRoot + '/seerr/config:/app/config'],
        environment: { TZ: tz },
        expose: [ports.seerr],
        ports: ['%s:5055:%s' % [lib.collections.ip.loopback, ports.seerr]],
        init: true,
      },

      [refs.sonarr.key]: {
        container_name: refs.sonarr.ext,
        image: 'lscr.io/linuxserver/sonarr@sha256:02b4d538d351d6e35882a021c08e8600fe95d28860fb1dd724b597166e7221ca',
        restart: restart,
        volumes: [
          bindRoot + '/sonarr/config:/config',
          sharedData + ':/data',
        ],
        environment: lsioEnv,
        healthcheck: httpHealth(ports.sonarr, '/ping'),
        expose: [ports.sonarr],
        ports: ['%s:8989:%s' % [lib.collections.ip.loopback, ports.sonarr]],
      },
    },
  },
}
