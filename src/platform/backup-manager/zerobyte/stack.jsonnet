// Reads /var/lib/docker/volumes off the host (a bind mount, not a docker network), so it
// owns no shared network. BASE_URL points at the control plane rather than at whichever
// host this copy runs on, so every instance advertises the same address. Only the
// Infisical secret stays as ${...}; env_files: ANSIBLE_SECRETS_FILE (default
// /dev/shm/zerobyte.env) -> SECRET__APP_SECRET.
local lib = import 'lib.libsonnet';
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
        BASE_URL: 'http://' + reg.hosts.littlebuddy.ip + ':' + std.toString(port),
        APP_SECRET: '${ZROBYT__APP_SECRET:?err}',
      },
      ports: [std.toString(port) + ':' + std.toString(port)],  // core infra, no proxy
      cap_add: ['SYS_ADMIN'],
      devices: ['/dev/fuse:/dev/fuse'],
      security_opt: ['apparmor:unconfined'],
    },
  }),
  [lib.SecretOrBootstrap('zerobyte')],
)
