// zerobyte — volume backup manager. Reads /var/lib/docker/volumes off the host
// (a bind mount, NOT a docker network), so it owns no shared network.
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Identity (name, port, version, derived app name) is baked in at compile time.
// Only genuine per-HOST values (the tailscale hostname) and the Infisical secret
// stay as ${...} for docker compose to interpolate at deploy.
local infra = import 'infra.libsonnet';

local stack = 'zerobyte';
local n = infra.net.names(stack);

local port = 4096;
local version = 'v0.39';

{
  name: stack,

  services: {
    app: {
      image: 'ghcr.io/nicotsx/zerobyte:' + version,
      container_name: n.container('app'),  // 'zerobyte-app'
      volumes: [
        '/etc/localtime:/etc/localtime:ro',
        '/var/lib/docker/volumes:/source/docker-volumes',  // the volumes it backs up
        'app:/var/lib/zerobyte',
      ],
      environment: {
        TZ: 'America/New_York',
        // Per-host: the node's tailscale hostname. Secret: from the deploy env.
        BASE_URL: 'http://${TAILSCALE_HOSTNAME:?err}:' + std.toString(port),
        APP_SECRET: '${SECRET__APP_SECRET:?err}',
      },
      ports: [infra.net.publish(port)],  // '4096:4096' — core infra, no proxy
      networks: {
        default: { aliases: [n.alias('app')] },
      },
      restart: 'unless-stopped',
      cap_add: ['SYS_ADMIN'],
      devices: ['/dev/fuse:/dev/fuse'],
    },
  },

  networks: infra.net.default(stack),  // private net (renamed default) 'zerobyte'

  volumes: {
    app: { name: n.volume('app') },  // 'zerobyte-app'
  },
}
