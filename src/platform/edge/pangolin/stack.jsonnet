local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'pangolin',

  // Only `init` takes the derived <project>_<role> name. The other three are dialled by
  // literal name from outside this stack — gerbil's own flags, the Traefik backends
  // Pangolin renders, and ops tooling — so each overrides container_name with its bare
  // role. All storage is a host bind mount, so this stack owns no volumes.
  init:: self.Service { role:: 'init' },
  pangolin:: self.Service { role:: 'pangolin', ext:: self.role },
  gerbil:: self.Service { role:: 'gerbil', ext:: self.role },
  traefik:: self.Service { role:: 'traefik', ext:: self.role },
};
local col = lib.collections;
local reg = lib.registry;

local pangolinVersion = 'ee-1.20.0';
local gerbilVersion = '1.4.2';
local traefikVersion = 'v3.6';

local configDir = lib.collections.dirs.docker.bindMounts + '/pangolin/config';

local geoliteMirror = 'https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/';
local fetchGeolite(db) =
  'if [ ! -f /mnt/config/GeoLite2-%(db)s.mmdb ]; then ' % { db: db } +
  'wget -qO /tmp/geolite-%(db)s.tar.gz %(mirror)sGeoLite2-%(db)s.tar.gz && ' % { db: db, mirror: geoliteMirror } +
  'tar -xzf /tmp/geolite-%(db)s.tar.gz -C /tmp && ' % { db: db } +
  'mv /tmp/GeoLite2-%(db)s_*/GeoLite2-%(db)s.mmdb /mnt/config/; ' % { db: db } +
  'fi';

// chmod 600 on acme.json MUST run last — a preceding `chmod -R 755 /mnt/config` would
// clobber it back to 755, breaking Traefik ACME.
local initScript = std.join(' && ', [
  'set -e',
  'mkdir -p /mnt/config/traefik/logs /mnt/config/letsencrypt',
  'touch /mnt/config/letsencrypt/acme.json',
  fetchGeolite('Country'),
  fetchGeolite('ASN'),
  'chmod -R 755 /mnt/config',
  'chmod 600 /mnt/config/letsencrypt/acme.json',
]);

local initDone = { [refs.init.key]: { condition: lib.collections.condition.completed } };

// Traefik's Cloudflare DNS-01 token is a bundle of its own (/traefik), shared with anything
// else that does DNS-01 rather than copied into this stack's bundle. One provider service
// serves one path, so it takes a second one; the injected names do not collide.
local secretsTraefik = col.role.SECRETS + '-traefik';
local secretsTraefikReady = {
  [secretsTraefik]: { condition: lib.collections.condition.started },
};
local pangolinHealthy = { [refs.pangolin.key]: { condition: lib.collections.condition.healthy } };

{
  compose: {
    name: refs.name,
    // The edge needs IPv6 on its bridge, which the plain private bridge does not carry.
    networks: { default: { name: refs.name, driver: 'bridge', enable_ipv6: true } },

    services: {
      [col.role.SECRETS]: lib.SecretsProvider('pangolin'),
      [secretsTraefik]: lib.SecretsProvider('cfApiDnsToken'),
      // One-shot: creates the config tree/perms + the GeoLite mmdbs (skipped after the first
      // run). It does not provision files/ content — that is the bind mounts below.
      [refs.init.key]: {
        container_name: refs.init.ext,
        image: 'docker.io/library/busybox:1.37.0',
        // Quoted: bare `no` is a YAML boolean and compose wants the string.
        restart: 'no',
        volumes: [configDir + ':/mnt/config'],
        command: ['sh', '-c', initScript],
      },

      [refs.pangolin.key]: {
        container_name: refs.pangolin.ext,
        image: 'docker.io/fosrl/pangolin:' + pangolinVersion,
        restart: lib.collections.restart.unlessStopped,
        depends_on: initDone + lib.secretsReady,
        mem_limit: '2g',
        mem_reservation: '512m',
        volumes: [
          configDir + ':/app/config',
          // Generated beside this file; the container paths keep the .yml names Pangolin
          // expects.
          './files/config.yaml:/app/config/config.yml:ro',
          './files/privateConfig.yaml:/app/config/privateConfig.yml:ro',
        ],
        // SERVER_SECRET and EMAIL_SMTP_PASS arrive from infisical-secrets and override
        // server.secret / email.smtp_pass, which config.yml ships blank.
        healthcheck: {
          test: ['CMD', 'curl', '-f', 'http://localhost:3001/api/v1/'],
          interval: '10s',
          timeout: '10s',
          retries: 15,
        },
      },

      [refs.gerbil.key]: {
        container_name: refs.gerbil.ext,
        image: 'docker.io/fosrl/gerbil:' + gerbilVersion,
        restart: lib.collections.restart.unlessStopped,
        depends_on: initDone + pangolinHealthy,
        command: [
          '--reachableAt=http://%s:3004' % refs.gerbil.ext,
          '--generateAndSaveKeyTo=/var/config/key',
          '--remoteConfig=http://%s:3001/api/v1/' % refs.pangolin.ext,
        ],
        volumes: [configDir + ':/var/config'],
        cap_add: ['NET_ADMIN', 'SYS_MODULE'],
        // Public edge ports — these are the host's 80/443, deliberately not loopback-bound.
        ports: [
          '51820:51820/udp',
          '21820:21820/udp',
          '443:443',
          // HTTP/3 QUIC
          '443:443/udp',
          '80:80',
          '22:22',
          '18022:18022',
        ],
      },

      // network_mode: service:gerbil — Traefik shares gerbil's netns so the public ports
      // above front it. Compose rejects networks on a service that shares another's netns,
      // so this one declares none.
      [refs.traefik.key]: {
        container_name: refs.traefik.ext,
        image: 'docker.io/library/traefik:' + traefikVersion,
        restart: lib.collections.restart.unlessStopped,
        network_mode: 'service:' + refs.gerbil.key,
        depends_on: initDone + pangolinHealthy + secretsTraefikReady,
        command: ['--configFile=/etc/traefik/traefik_config.yml'],
        // CF_DNS_API_TOKEN arrives from the /traefik bundle above; lego reads it straight
        // out of the environment for the DNS-01 challenge.
        volumes: [
          // Generated beside this file; the container paths keep the .yml names traefik
          // expects.
          './files/traefik_config.yaml:/etc/traefik/traefik_config.yml:ro',
          './files/dynamic_config.yaml:/etc/traefik/dynamic_config.yml:ro',
          configDir + '/letsencrypt:/letsencrypt',
          configDir + '/traefik/logs:/var/log/traefik',
        ],
      },
    },
  },
}
