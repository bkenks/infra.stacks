// Reads /var/lib/docker/volumes off the host (a bind mount, not a docker network), so it
// owns no shared network. Only per-host values (tailscale hostname) and the Infisical secret
// stay as ${...}; env_files: ANSIBLE_SECRETS_FILE (default /dev/shm/zerobyte.env) ->
// SECRET__APP_SECRET; tailscale.env -> TAILSCALE_HOSTNAME (per-host, self-refreshing).
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'zerobyte';
local port = 4096;
local version = 'v0.40';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/nicotsx/zerobyte:' + version,
      volumes_:: { app: '/var/lib/zerobyte' },
      mounts_:: [
        '/etc/localtime:/etc/localtime:ro',
        '/var/lib/docker/volumes:/source/docker-volumes',
      ],
      environment: {
        TZ: 'America/New_York',
        BASE_URL: 'http://${TAILSCALE_HOSTNAME:?err}:' + std.toString(port),
        APP_SECRET: '${ZROBYT__APP_SECRET:?err}',
      },
      ports: [std.toString(port) + ':' + std.toString(port)],  // core infra, no proxy
      cap_add: ['SYS_ADMIN'],
      devices: ['/dev/fuse:/dev/fuse'],
    },
  }),
  [lib.SecretOrBootstrap('zerobyte'), reg.hostFacts],
)
