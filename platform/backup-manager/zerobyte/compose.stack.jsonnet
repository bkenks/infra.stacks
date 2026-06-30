// zerobyte — volume backup manager. Reads /var/lib/docker/volumes off the host
// (a bind mount, NOT a docker network), so it owns no shared network.
//
// Source of truth for the child: renders to compose.stack.yaml (do not edit the
// YAML). Identity (name, port, version, derived app name) is baked in at compile
// time. Only genuine per-HOST values (the tailscale hostname) and the Infisical
// secret stay as ${...} for docker compose to interpolate at deploy — the parent
// compose.jsonnet declares the env_files that supply them.
local lib = import 'lib.libsonnet';

local stack = 'zerobyte';
local n = lib.compose.names(stack);
local roles = lib.compose.roles;

local port = 4096;
local version = 'v0.40';

{
  name: stack,

  services: {
    [roles.app]: {
      image: 'ghcr.io/nicotsx/zerobyte:' + version,
      container_name: n.container(roles.app),
      volumes: [
        '/etc/localtime:/etc/localtime:ro',
        '/var/lib/docker/volumes:/source/docker-volumes',  // the volumes it backs up
        roles.app + ':/var/lib/zerobyte',
      ],
      environment: {
        TZ: 'America/New_York',
        // Per-host: the node's tailscale hostname. Secret: from the deploy env.
        BASE_URL: 'http://${TAILSCALE_HOSTNAME:?err}:' + std.toString(port),
        APP_SECRET: '${ZROBYT__APP_SECRET:?err}',
      },
      ports: [lib.compose.publish(port)],  // '4096:4096' — core infra, no proxy
      networks: {
        default: { aliases: [n.alias(roles.app)] },
      },
      restart: 'unless-stopped',
      cap_add: ['SYS_ADMIN'],
      devices: ['/dev/fuse:/dev/fuse'],
    },
  },

  networks: n.network,  // private net (renamed default) 'zerobyte'

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },  // 'zerobyte-app'
  },
}
