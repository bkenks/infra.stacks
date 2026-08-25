// Reads /var/lib/docker/volumes off the host (a bind mount, not a docker network), so it
// owns no shared network. BASE_URL points at the control plane rather than at whichever
// host this copy runs on, so every instance advertises the same address.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'zerobyte',
  // Brought up by the control plane before the agent exists to render anything.
  envFiles:: [lib.SecretOrBootstrap('zerobyte')],

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
};

local version = 'v0.40';
local port = '4096';

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/nicotsx/zerobyte:' + version,
        restart: lib.collections.restart.unlessStopped,
        volumes: [
          refs.appData.mount('/var/lib/zerobyte'),
          '/etc/localtime:/etc/localtime:ro',
          '/var/lib/docker/volumes:/source/docker-volumes',
        ],
        environment: {
          TZ: 'America/New_York',
          BASE_URL: 'http://%s:%s' % [lib.registry.endpoint.hostGroup.littlebuddy.ref, port],
          APP_SECRET: '${ZROBYT__APP_SECRET:?err}',
        },
        // Core infra, no proxy in front of it.
        ports: [port + ':' + port],
        cap_add: ['SYS_ADMIN'],
        devices: ['/dev/fuse:/dev/fuse'],
        security_opt: ['apparmor:unconfined'],
      },
    },
  },
}
