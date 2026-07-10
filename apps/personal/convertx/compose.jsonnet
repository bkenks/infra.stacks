// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'convertx';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

local port = 3000;

local manifest = {
  name: stack,

  services: {
    [app]: {
      // Upstream publishes no version tags — unpinned/`latest`.
      image: 'ghcr.io/c4illin/convertx',
      container_name: n.container(app),
      volumes: [reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/convertx:/app/data'],
      environment: {
        JWT_SECRET: '${CONVERTX_JWT_SECRET:?err}',
      },
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
    + s.network.join(reg.sharedNetworks.proxy),
};

c.render(stack, manifest, [secrets.convertx.path])
