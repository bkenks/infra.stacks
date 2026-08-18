// Reads /var/lib/docker/volumes off the host (a bind mount, not a docker network), so it
// owns no shared network. BASE_URL points at the control plane rather than at whichever
// host this copy runs on, so every instance advertises the same address.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = 'v0.40';
local port = '4096';

{
  name: refs.name,
  networks: refs.networks,
  volumes: refs.appData.declare,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'ghcr.io/nicotsx/zerobyte:' + version,
      restart: lib.restart.unlessStopped,
      volumes: [
        refs.appData.mount('/var/lib/zerobyte'),
        '/etc/localtime:/etc/localtime:ro',
        '/var/lib/docker/volumes:/source/docker-volumes',
      ],
      environment: {
        TZ: 'America/New_York',
        BASE_URL: 'http://%s:%s' % [lib.registry.hosts.littlebuddy.ip, port],
        APP_SECRET: '${ZROBYT__APP_SECRET:?err}',
      },
      // Core infra, no proxy in front of it.
      ports: [port + ':' + port],
      cap_add: ['SYS_ADMIN'],
      devices: ['/dev/fuse:/dev/fuse'],
      security_opt: ['apparmor:unconfined'],
    },
  },
}
