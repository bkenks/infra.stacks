// pangolin — VPS edge: Pangolin (control plane), Gerbil (WireGuard, owns public
// 80/443/51820/21820), Traefik (HTTP routing + ACME) for this edge host only.
//
// NOT the per-host platform/edge/traefik stack — don't deploy both on the same host
// (port conflict; Gerbil owns 80/443 here).
//
// Naming deviation: service keys and container_names are literal ('pangolin', 'gerbil',
// 'traefik'), so the library's derived <stack>_<role> container_name is overridden on
// each of the three — Pangolin/Gerbil hardcode each other's hostnames in their startup
// flags, and files/config.libsonnet's backend URLs assume these exact names; renaming
// breaks service discovery. Traefik's `network_mode: service:gerbil` also requires
// gerbil's compose key to be literally 'gerbil'. Intentional — see README.md.
//
// Storage: one shared host dir (bind mounts, not named volumes — Pangolin/Gerbil/
// Traefik expect to read/write this tree by upstream design). `init` creates the
// tree/perms first; files/*.jsonnet-rendered config layers on as read-only bind
// mounts (git-tracked); runtime state (keys, certs, GeoLite DBs, logs, db) stays host-only.
//
// Single instance: the VPS edge on rick, reached at pangolin.ktbcloud.com. The config is
// rendered from files/config.libsonnet into files/ and mounted read-only below.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;

local name = 'pangolin';
local configDir = reg.dirs.docker.root + reg.dirs.docker.bindMounts + '/pangolin/config';

// Every service name here is app-specific rather than a reg.role — the three long-lived
// ones are dialed by these literal names from outside this file.
local initKey = 'init';
local pangolinKey = 'pangolin';
local gerbilKey = 'gerbil';
local traefikKey = 'traefik';

local pangolinVersion = 'ee-1.20.0';
local gerbilVersion = '1.4.2';
local traefikVersion = 'v3.6';

// Same mirror Pangolin's installer uses (no MaxMind license key needed). Tarball
// extracts to a versioned dir (GeoLite2-<name>_<date>/) — the mv glob below matches that.
local geoliteMirror = 'https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/';
local fetchGeolite(name) =
  'if [ ! -f /mnt/config/GeoLite2-' + name + '.mmdb ]; then ' +
  'wget -qO /tmp/geolite-' + name + '.tar.gz ' + geoliteMirror + 'GeoLite2-' + name + '.tar.gz && ' +
  'tar -xzf /tmp/geolite-' + name + '.tar.gz -C /tmp && ' +
  'mv /tmp/GeoLite2-' + name + '_*/GeoLite2-' + name + '.mmdb /mnt/config/; ' +
  'fi';

// chmod 600 on acme.json MUST run last — a preceding `chmod -R 755 /mnt/config`
// would clobber it back to 755, breaking Traefik ACME.
local initScript =
  'set -e && ' +
  'mkdir -p /mnt/config/traefik/logs /mnt/config/letsencrypt && ' +
  'touch /mnt/config/letsencrypt/acme.json && ' +
  fetchGeolite('Country') + ' && ' +
  fetchGeolite('ASN') + ' && ' +
  'chmod -R 755 /mnt/config && ' +
  'chmod 600 /mnt/config/letsencrypt/acme.json';

lib.render(
  name,

  lib.Stack(
    name,
    function(ref) {
      // One-shot: creates config tree/perms + GeoLite mmdbs (skipped after first run).
      // Doesn't provision files/ content — that's the bind mounts below. Nothing dials it,
      // so it keeps the derived name pangolin_init; only `restart` is overridden — quoted
      // because bare `no` is a YAML boolean, and Compose wants the string.
      [initKey]: lib.Service {
        image: 'docker.io/library/busybox:1.37.0',
        mounts_:: [configDir + ':/mnt/config'],
        command: ['sh', '-c', initScript],
        restart: 'no',
      },

      [pangolinKey]: lib.Service {
        image: 'docker.io/fosrl/pangolin:' + pangolinVersion,
        // Bare, not pangolin_pangolin: gerbil's --remoteConfig flag and the rendered
        // Traefik backends already dial this exact hostname.
        container_name: pangolinKey,
        depends_on: { [initKey]: { condition: 'service_completed_successfully' } },
        mem_limit: '2g',
        mem_reservation: '512m',
        mounts_:: [
          configDir + ':/app/config',
          // files/configs.config.yaml (generated); container path keeps the .yml name Pangolin
          // expects. privateConfig.yml is a hand-maintained, shared placeholder.
          './files/configs.config.yaml:/app/config/config.yml:ro',
          './files/configs.privateConfig.yml:/app/config/privateConfig.yml:ro',
        ],
        environment: {
          // Overrides server.secret / email.smtp_pass (config.yml ships both blank).
          SERVER_SECRET: '${SERVER_SECRET:?err}',
          EMAIL_SMTP_PASS: '${EMAIL_SMTP_PASS:?err}',
        },
        healthcheck: {
          test: ['CMD', 'curl', '-f', 'http://localhost:3001/api/v1/'],
          interval: '10s',
          timeout: '10s',
          retries: 15,
        },
      },

      [gerbilKey]: lib.Service {
        image: 'docker.io/fosrl/gerbil:' + gerbilVersion,
        // Bare, not pangolin_gerbil: its own --reachableAt flag and traefik's
        // network_mode below both name it literally.
        container_name: gerbilKey,
        depends_on: {
          [initKey]: { condition: 'service_completed_successfully' },
          [pangolinKey]: { condition: 'service_healthy' },
        },
        command: [
          '--reachableAt=http://gerbil:3004',
          '--generateAndSaveKeyTo=/var/config/key',
          '--remoteConfig=http://pangolin:3001/api/v1/',
        ],
        mounts_:: [configDir + ':/var/config'],
        cap_add: ['NET_ADMIN', 'SYS_MODULE'],
        // Public edge ports — these are the host's 80/443, deliberately not loopback-bound.
        ports: [
          '51820:51820/udp',
          '21820:21820/udp',
          '443:443',
          '443:443/udp',  // HTTP/3 QUIC
          '80:80',
          '22:22',
        ],
      },

      // network_mode: service:gerbil — Traefik shares gerbil's netns so the public ports
      // above front it.
      [traefikKey]: lib.Service {
        image: 'docker.io/library/traefik:' + traefikVersion,
        // Bare, not pangolin_traefik: the name is already referenced from outside this
        // stack (ops tooling and the shared edge conventions).
        container_name: traefikKey,
        network_mode: 'service:' + gerbilKey,
        depends_on: {
          [initKey]: { condition: 'service_completed_successfully' },
          [pangolinKey]: { condition: 'service_healthy' },
        },
        command: ['--configFile=/etc/traefik/traefik_config.yml'],
        environment: {
          // CF_DNS_API_TOKEN for DNS-01 ACME (lego reads from env); shared with
          // platform/edge/traefik, not duplicated into this stack's own env.
          CF_DNS_API_TOKEN: '${CF_DNS_API_TOKEN:?err}',
        },
        mounts_:: [
          // files/configs.*.yaml; container paths keep the .yml names traefik expects.
          './files/configs.traefik_config.yaml:/etc/traefik/traefik_config.yml:ro',
          './files/configs.dynamic_config.yaml:/etc/traefik/dynamic_config.yml:ro',
          configDir + '/letsencrypt:/letsencrypt',
          configDir + '/traefik/logs:/var/log/traefik',
        ],
      },
    },

    // Replaces the whole top-level networks block: the edge needs IPv6 on its bridge,
    // which the library's plain `{ default: { name: name } }` does not carry.
    { default: { name: name, driver: 'bridge', enable_ipv6: true } },
  ),

  [lib.Secret('pangolin'), lib.Secret('cloudflare__dns-api-token')],
)
