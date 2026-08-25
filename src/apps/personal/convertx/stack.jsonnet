local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'convertx',

  app:: self.Service { role:: lib.collections.role.APP },
};

local port = '3000';
local dataDir = lib.collections.dirs.docker.bindMounts + '/apps/convertx';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('convertx'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        // Upstream publishes no version tags — unpinned/`latest`.
        image: 'ghcr.io/c4illin/convertx',
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady,
        volumes: [dataDir + ':/app/data'],
        // JWT_SECRET arrives from infisical-secrets.
        expose: [port],
        ports: ['%s:18001:%s' % [lib.collections.ip.loopback, port]],
      },
    },
  },
}
