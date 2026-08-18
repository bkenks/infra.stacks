local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local port = '3000';
local dataDir = lib.dirs.docker.bindMounts + '/apps/convertx';

{
  name: refs.name,
  networks: refs.networks,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      // Upstream publishes no version tags — unpinned/`latest`.
      image: 'ghcr.io/c4illin/convertx',
      restart: lib.restart.unlessStopped,
      volumes: [dataDir + ':/app/data'],
      environment: {
        JWT_SECRET: '${CONVERTX_JWT_SECRET:?err}',
      },
      expose: [port],
      ports: ['%s:18001:%s' % [lib.ip.loopback, port]],
    },
  },
}
