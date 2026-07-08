// mazanoke — image compression tool (mazanoke.<domains.ktbinternal>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable. Fully stateless —
// no volumes, no secrets, no DB.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'mazanoke';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

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
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add(stack, stack, port),
    },
  },

  networks:
    s.network.default
    + s.network.join('proxy'),
}
