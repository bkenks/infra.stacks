// pangolin — VPS edge: Pangolin (control plane), Gerbil (WireGuard, owns public
// 80/443/51820/21820), Traefik (HTTP routing + ACME) for this edge host only.
//
// NOT the per-host platform/edge/traefik stack — don't deploy both on the same host
// (port conflict; Gerbil owns 80/443 here).
//
// Naming deviation: service keys/container_names are literal ('pangolin', 'gerbil',
// 'traefik'), not run through the naming helper — Pangolin/Gerbil hardcode each
// other's hostnames in their startup flags, and dynamic_config.jsonnet's backend URLs
// assume these exact names; renaming breaks service discovery. Traefik's
// `network_mode: service:gerbil` also requires gerbil's compose key to be literally
// 'gerbil'. Intentional — see README.md.
//
// Storage: one shared host dir (bind mounts, not named volumes — Pangolin/Gerbil/
// Traefik expect to read/write this tree by upstream design). `init` creates the
// tree/perms first; files/*.jsonnet-rendered config layers on as read-only bind
// mounts (git-tracked); runtime state (keys, certs, GeoLite DBs, logs, db) stays host-only.
//
// TWO HOSTS, ONE STACK: the config differs between instances only by the domain it's
// reached at, so it's rendered into files/cloud/ (pangolin.ktbcloud.com, rick) and
// files/internal/ (pangolin.ktbinternal.com, bill) from the same ../config.libsonnet.
// The mounts below select one via ${PANGOLIN_VARIANT}, set per instance in Komodo's stack
// environment (cloud | internal). Same proof as infisical-agent's ${AGENT_HOST}: Komodo's
// env reaches interpolation inside this included file. Everything else is identical.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;
local dv = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts;

local stack = 'pangolin';
local s = c.stack(stack);
local sharedProxy = reg.sharedNetworks.proxy;
local configDir = dv + '/pangolin/config';


local pangolinVersion = 'ee-1.19.4';
local gerbilVersion = '1.4.2';
local gerbilName = 'gerbil';
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

local manifest = {
  name: stack,

  services: {
    // One-shot: creates config tree/perms + GeoLite mmdbs (skipped after first run).
    // Doesn't provision files/ content — that's the bind mounts below.
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
        // files/<variant>/config.yaml (git-tracked); container path keeps the .yml name
        // Pangolin expects. privateConfig.yml is hand-maintained, shared, and variant-agnostic.
        './files/${PANGOLIN_VARIANT:?set PANGOLIN_VARIANT to cloud or internal}/config.yaml:/app/config/config.yml:ro',
        './files/privateConfig.yml:/app/config/privateConfig.yml:ro',
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
      networks: { default: { aliases: ['pangolin'] } },
    },

    gerbil: {
      image: 'docker.io/fosrl/gerbil:' + gerbilVersion,
      container_name: gerbilName,
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
        '22:22',
      ],
      // Also joins shared-edge so Traefik (network_mode: service:gerbil, i.e.
      // it shares gerbil's netns) can reach authentik_server:9000 for the raw
      // auth.ktbcloud.com router in files/dynamic_config.yml. authentik owns
      // this network; pangolin is a consumer (the external decl is in the
      // top-level networks block below via network.join).
      networks: { default: { aliases: [gerbilName] } }
                + s.network.attach(sharedProxy.name,  gerbilName),
    },

    // network_mode: service:gerbil — Traefik can't also declare networks: (Compose
    // disallows combining the two on the same service).
    traefik: {
      image: 'docker.io/library/traefik:' + traefikVersion,
      container_name: 'traefik',
      restart: 'unless-stopped',
      network_mode: 'service:' + gerbilName,
      depends_on: {
        init: { condition: 'service_completed_successfully' },
        pangolin: { condition: 'service_healthy' },
      },
      command: ['--configFile=/etc/traefik/traefik_config.yml'],
      environment: {
        // CF_DNS_API_TOKEN for DNS-01 ACME (lego reads from env); shared with
        // platform/edge/traefik, not duplicated into this stack's own env.
        CF_DNS_API_TOKEN: '${CF_DNS_API_TOKEN:?err}',
      },
      volumes: [
        // files/<variant>/*.yaml; container paths keep the .yml names traefik expects.
        './files/${PANGOLIN_VARIANT:?set PANGOLIN_VARIANT to cloud or internal}/traefik_config.yaml:/etc/traefik/traefik_config.yml:ro',
        './files/${PANGOLIN_VARIANT:?set PANGOLIN_VARIANT to cloud or internal}/dynamic_config.yaml:/etc/traefik/dynamic_config.yml:ro',
        configDir + '/letsencrypt:/letsencrypt',
        configDir + '/traefik/logs:/var/log/traefik',
      ],
    },
  },

  networks: {
    default: { name: stack, driver: 'bridge', enable_ipv6: true },
  } + s.network.join(reg.sharedNetworks.proxy),  // external shared-edge (owned by authentik)
};

c.render(stack, manifest, [
  secrets.pangolin.path,
  secrets['cloudflare__dns-api-token'].path,
])
