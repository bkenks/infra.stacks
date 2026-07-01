// mazanoke — image compression tool (mazanoke.<rootDomain>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable. Fully stateless —
// no volumes, no secrets, no DB.
local lib = import 'lib.libsonnet';

local stack = 'mazanoke';
local n = lib.compose.names(stack);
local app = lib.compose.roles.app;

local version = 'v1.1.5';
local port = 80;

{
  name: stack,

  services: {
    [app]: {
      image: 'ghcr.io/civilblur/mazanoke:' + version,
      container_name: n.container(app),
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
