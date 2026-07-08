// zerobyte — volume backup manager. Reads /var/lib/docker/volumes off the host
// (a bind mount, NOT a docker network), so it owns no shared network.
//
// Source of truth for the child: renders to compose.stack.yaml (do not edit the
// YAML). Identity (name, port, version, derived app name) is baked in at compile
// time. Only genuine per-HOST values (the tailscale hostname) and the Infisical
// secret stay as ${...} for docker compose to interpolate at deploy — the parent
// compose.jsonnet declares the env_files that supply them.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'zerobyte';
local s = c.stack(stack);
local n = s.names;
local roles = reg.roles;

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
      ports: [std.toString(port) + ':' + std.toString(port)],  // '4096:4096' — core infra, no proxy
      networks: {
        default: { aliases: [n.container(roles.app)] },
      },
      restart: 'unless-stopped',
      cap_add: ['SYS_ADMIN'],
      devices: ['/dev/fuse:/dev/fuse'],
    },
  },

  networks: s.network.default,  // private net (renamed default) 'zerobyte'

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },  // 'zerobyte_app'
  },
}
