// convertx — file conversion tool (convertx.<rootDomain>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable.
local lib = import 'lib.libsonnet';

local stack = 'convertx';
local n = lib.compose.names(stack);
local app = lib.compose.roles.app;

local port = 3000;

{
  name: stack,

  services: {
    [app]: {
      // Upstream publishes no version tags today — stays unpinned/`latest`
      // until the project ships one.
      image: 'ghcr.io/c4illin/convertx',
      container_name: n.container(app),
      volumes: [lib.registry.dockerVolumes + '/apps/convertx:/app/data'],
      environment: {
        // Secret — interpolated from /dev/shm/convertx.env (parent include.env_file)
        JWT_SECRET: '${CONVERTX_JWT_SECRET:?err}',
      },
      restart: 'unless-stopped',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.alias(app)] },
        [lib.compose.netName('proxy')]: { aliases: [n.alias(app)] },
      },
      labels: lib.mixins.proxyAdd(stack, stack, port),
    },
  },

  networks:
    n.network
    + lib.compose.join('proxy'),
}
