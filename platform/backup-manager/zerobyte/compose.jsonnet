// Reads /var/lib/docker/volumes off the host (a bind mount, not a docker network), so it
// owns no shared network. Only per-host values (tailscale hostname) and the Infisical secret
// stay as ${...}; env_files: ANSIBLE_SECRETS_FILE (default /dev/shm/zerobyte.env) ->
// SECRET__APP_SECRET; tailscale.env -> TAILSCALE_HOSTNAME (per-host, self-refreshing).
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'zerobyte';
local s = c.stack(stack);
local n = s.names;
local roles = reg.roles;

local port = 4096;
local version = 'v0.40';

local manifest = {
  name: stack,

  services: {
    [roles.app]: {
      image: 'ghcr.io/nicotsx/zerobyte:' + version,
      container_name: n.container(roles.app),
      volumes: [
        '/etc/localtime:/etc/localtime:ro',
        '/var/lib/docker/volumes:/source/docker-volumes',
        roles.app + ':/var/lib/zerobyte',
      ],
      environment: {
        TZ: 'America/New_York',
        BASE_URL: 'http://${TAILSCALE_HOSTNAME:?err}:' + std.toString(port),
        APP_SECRET: '${ZROBYT__APP_SECRET:?err}',
      },
      ports: [std.toString(port) + ':' + std.toString(port)],  // core infra, no proxy
      networks: {
        default: { aliases: [n.container(roles.app)] },
      },
      restart: 'unless-stopped',
      cap_add: ['SYS_ADMIN'],
      devices: ['/dev/fuse:/dev/fuse'],
    },
  },

  networks: s.network.default,

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },
  },
};

c.render(stack, manifest, [
  c.envPath.platform('zerobyte'),
  reg.envFiles.tailscale,
])
