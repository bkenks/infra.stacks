local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local port = '3000';
local dataDir = lib.collections.dirs.docker.bindMounts + '/apps/convertx';

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        // Upstream publishes no version tags — unpinned/`latest`.
        image: 'ghcr.io/c4illin/convertx',
        restart: lib.collections.restart.unlessStopped,
        volumes: [dataDir + ':/app/data'],
        environment: {
          JWT_SECRET: '${CONVERTX_JWT_SECRET:?err}',
        },
        expose: [port],
        ports: ['%s:18001:%s' % [lib.collections.ip.loopback, port]],
      },
    },
  },
}
