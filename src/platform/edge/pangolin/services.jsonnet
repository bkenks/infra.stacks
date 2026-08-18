local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local pangolinVersion = 'ee-1.20.0';
local gerbilVersion = '1.4.2';
local traefikVersion = 'v3.6';

local configDir = lib.dirs.docker.bindMounts + '/pangolin/config';

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

local initDone = { [refs.init.key]: { condition: lib.condition.completed } };
local pangolinHealthy = { [refs.pangolin.key]: { condition: lib.condition.healthy } };

{
  name: refs.name,
  // The edge needs IPv6 on its bridge, which the plain private bridge does not carry.
  networks: { default: refs.networks.default { driver: 'bridge', enable_ipv6: true } },

  services: {
    // One-shot: creates the config tree/perms + the GeoLite mmdbs (skipped after the first
    // run). It does not provision files/ content — that is the bind mounts below.
    [refs.init.key]: {
      container_name: refs.init.container,
      image: 'docker.io/library/busybox:1.37.0',
      // Quoted: bare `no` is a YAML boolean and compose wants the string.
      restart: 'no',
      volumes: [configDir + ':/mnt/config'],
      command: ['sh', '-c', initScript],
    },

    [refs.pangolin.key]: {
      container_name: refs.pangolin.container,
      image: 'docker.io/fosrl/pangolin:' + pangolinVersion,
      restart: lib.restart.unlessStopped,
      depends_on: initDone,
      mem_limit: '2g',
      mem_reservation: '512m',
      volumes: [
        configDir + ':/app/config',
        // Generated beside this file; the container paths keep the .yml names Pangolin
        // expects.
        './files/config.yaml:/app/config/config.yml:ro',
        './files/privateConfig.yaml:/app/config/privateConfig.yml:ro',
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

    [refs.gerbil.key]: {
      container_name: refs.gerbil.container,
      image: 'docker.io/fosrl/gerbil:' + gerbilVersion,
      restart: lib.restart.unlessStopped,
      depends_on: initDone + pangolinHealthy,
      command: [
        '--reachableAt=http://%s:3004' % refs.gerbil.container,
        '--generateAndSaveKeyTo=/var/config/key',
        '--remoteConfig=http://%s:3001/api/v1/' % refs.pangolin.container,
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
      container_name: refs.traefik.container,
      image: 'docker.io/library/traefik:' + traefikVersion,
      restart: lib.restart.unlessStopped,
      network_mode: 'service:' + refs.gerbil.key,
      depends_on: initDone + pangolinHealthy,
      command: ['--configFile=/etc/traefik/traefik_config.yml'],
      environment: {
        // CF_DNS_API_TOKEN for DNS-01 ACME (lego reads it from the environment); shared
        // with platform/edge/traefik rather than duplicated into this stack's own bundle.
        CF_DNS_API_TOKEN: '${CF_DNS_API_TOKEN:?err}',
      },
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
}
