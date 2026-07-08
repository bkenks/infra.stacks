// pangolin — VPS edge: Pangolin (control plane), Gerbil (WireGuard tunnel
// server, owns the public 80/443/51820/21820 ports), Traefik (HTTP routing +
// Let's Encrypt for THIS edge host only). Renders to compose.stack.yaml.
//
// NOT the per-host platform/edge/traefik stack — that one must not be deployed
// on the same host as this one (both want 80/443; Gerbil owns them here).
//
// Naming deviation: service keys ('pangolin', 'gerbil', 'traefik') and their
// container_names are literal, NOT run through lib.compose.names(). Pangolin
// and Gerbil hardcode each other's hostnames in their own startup flags
// (gerbil's --remoteConfig/--reachableAt below) and files/dynamic_config.yml's
// backend URLs assume they resolve to exactly 'pangolin'/'gerbil'/'traefik' —
// renaming breaks service discovery. Traefik's `network_mode: service:gerbil`
// also requires gerbil's compose key to be literally 'gerbil' (Compose syntax,
// not just DNS). This is the one stack in the repo that deviates from the
// <stack>_<role> convention, and it's intentional — see README.md.
//
// Storage: everything lives under one shared host directory (dv path below),
// same "all bind mounts, no named volumes, one shared dir across services"
// style as apps/media/stream's `sharedData` — Pangolin/Gerbil/Traefik
// read/write into this tree by upstream design, so splitting it into per-
// service named volumes would fight that. `init` creates the tree with the
// right permissions before the real services start; the human-maintained
// YAML config (files/) is layered on top as read-only bind mounts from this
// repo so it's git-tracked, while runtime state (keys, certs, GeoLite DBs,
// logs, Pangolin's own db) stays host-only.
local lib = import 'lib.libsonnet';
local dv = lib.registry.dockerVolumes;

local stack = 'pangolin';
local configDir = dv + '/pangolin/config';

local pangolinVersion = '1.19.4';
local gerbilVersion = '1.4.2';
local traefikVersion = 'v3.6';

// Same community redistribution mirror Pangolin's own installer downloads
// these from (pulled from the installer binary's strings — not MaxMind
// directly, so no license key needed). Each tarball extracts into a
// versioned dir (e.g. GeoLite2-Country_<date>/); the mv globs match that.
local geoliteMirror = 'https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/';
local fetchGeolite(name) =
  'if [ ! -f /mnt/config/GeoLite2-' + name + '.mmdb ]; then ' +
  'wget -qO /tmp/geolite-' + name + '.tar.gz ' + geoliteMirror + 'GeoLite2-' + name + '.tar.gz && ' +
  'tar -xzf /tmp/geolite-' + name + '.tar.gz -C /tmp && ' +
  'mv /tmp/GeoLite2-' + name + '_*/GeoLite2-' + name + '.mmdb /mnt/config/; ' +
  'fi';

// chmod 600 on acme.json MUST run last — a preceding `chmod -R 755
// /mnt/config` would clobber it right back to 755 (this bit us once already:
// Traefik refused ACME with "permissions 755 for /letsencrypt/acme.json are
// too open, please use 600", which then cascaded into "nonexistent
// certificate resolver" on every router since the resolver never initialized).
local initScript =
  'set -e && ' +
  'mkdir -p /mnt/config/traefik/logs /mnt/config/letsencrypt && ' +
  'touch /mnt/config/letsencrypt/acme.json && ' +
  fetchGeolite('Country') + ' && ' +
  fetchGeolite('ASN') + ' && ' +
  'chmod -R 755 /mnt/config && ' +
  'chmod 600 /mnt/config/letsencrypt/acme.json';

{
  name: stack,

  services: {
    // init — one-shot: creates the shared config tree with the right
    // directory structure/permissions before pangolin/gerbil/traefik start,
    // and downloads the GeoLite2 mmdb files on first run only (skipped once
    // they exist on the persistent host dir). Does NOT provision the rest of
    // the config content — that's the files/ bind mounts below.
    init: {
      image: 'docker.io/library/busybox:1.37.0',
      container_name: 'pangolin_init',
      volumes: [configDir + ':/mnt/config'],
      command: ['sh', '-c', initScript],
      restart: 'no',
    },

    pangolin: {
      image: 'docker.io/fosrl/pangolin:' + pangolinVersion,
      container_name: 'pangolin',
      restart: 'unless-stopped',
      depends_on: { init: { condition: 'service_completed_successfully' } },
      mem_limit: '2g',
      mem_reservation: '512m',
      volumes: [
        configDir + ':/app/config',
        './files/config.yml:/app/config/config.yml:ro',
        './files/privateConfig.yml:/app/config/privateConfig.yml:ro',
      ],
      environment: {
        // Secrets — interpolated from /dev/shm/pangolin.env (parent
        // include.env_file). Pangolin reads these as direct env-var
        // overrides for server.secret / email.smtp_pass (docs.pangolin.net
        // config-file) — config.yml ships with both blank.
        SERVER_SECRET: '${SERVER_SECRET:?err}',
        EMAIL_SMTP_PASS: '${EMAIL_SMTP_PASS:?err}',
      },
      healthcheck: {
        test: ['CMD', 'curl', '-f', 'http://localhost:3001/api/v1/'],
        interval: '10s',
        timeout: '10s',
        retries: 15,
      },
      networks: { default: { aliases: ['pangolin'] } },
    },

    gerbil: {
      image: 'docker.io/fosrl/gerbil:' + gerbilVersion,
      container_name: 'gerbil',
      restart: 'unless-stopped',
      depends_on: {
        init: { condition: 'service_completed_successfully' },
        pangolin: { condition: 'service_healthy' },
      },
      command: [
        '--reachableAt=http://gerbil:3004',
        '--generateAndSaveKeyTo=/var/config/key',
        '--remoteConfig=http://pangolin:3001/api/v1/',
      ],
      volumes: [configDir + ':/var/config'],
      cap_add: ['NET_ADMIN', 'SYS_MODULE'],
      ports: [
        '51820:51820/udp',
        '21820:21820/udp',
        '443:443',
        '443:443/udp',  // HTTP/3 QUIC
        '80:80',
      ],
      // Also joins shared-edge so Traefik (network_mode: service:gerbil, i.e.
      // it shares gerbil's netns) can reach authentik_server:9000 for the raw
      // auth.ktbcloud.com router in files/dynamic_config.yml. authentik owns
      // this network; pangolin is a consumer (the external decl is in the
      // top-level networks block below via compose.join).
      networks: { default: { aliases: ['gerbil'] } }
                + lib.compose.serviceNetwork(lib.registry.sharedNetworks.edge.name, 'gerbil'),
    },

    // network_mode: service:gerbil means Traefik's ports appear on gerbil —
    // it can't also declare its own `networks:` (Compose disallows combining
    // network_mode with networks on the same service).
    traefik: {
      image: 'docker.io/library/traefik:' + traefikVersion,
      container_name: 'traefik',
      restart: 'unless-stopped',
      network_mode: 'service:gerbil',
      depends_on: {
        init: { condition: 'service_completed_successfully' },
        pangolin: { condition: 'service_healthy' },
      },
      command: ['--configFile=/etc/traefik/traefik_config.yml'],
      environment: {
        // Secret — CF_DNS_API_TOKEN for the Cloudflare DNS-01 ACME challenge
        // (lego reads it from the container env). Interpolated from
        // /dev/shm/cloudflare__dns-api-token.env (parent include.env_file) —
        // shared with platform/edge/traefik, not duplicated into this
        // stack's own pangolin.env/Infisical folder.
        CF_DNS_API_TOKEN: '${CF_DNS_API_TOKEN:?err}',
      },
      volumes: [
        './files/traefik_config.yml:/etc/traefik/traefik_config.yml:ro',
        './files/dynamic_config.yml:/etc/traefik/dynamic_config.yml:ro',
        configDir + '/letsencrypt:/letsencrypt',
        configDir + '/traefik/logs:/var/log/traefik',
      ],
    },
  },

  networks: {
    default: { name: stack, driver: 'bridge', enable_ipv6: true },
  } + lib.compose.join('edge'),  // external shared-edge (owned by authentik)
}
