// Compiles to stack.compose.yaml and stack.services.yaml — do not edit the YAML.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'convertx';
local port = 3000;
local dataDir = reg.dirs.docker.root + reg.dirs.docker.bindMounts + '/apps/convertx';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      // Upstream publishes no version tags — unpinned/`latest`.
      image: 'ghcr.io/c4illin/convertx',
      mounts_:: [dataDir + ':/app/data'],
      environment: {
        JWT_SECRET: '${CONVERTX_JWT_SECRET:?err}',
      },
      expose: [std.toString(port)],
      ports: ['%s:18001:%s' % [reg.ips.loopback, port]],
    },
  }),
  [lib.Secret('convertx')],
)
