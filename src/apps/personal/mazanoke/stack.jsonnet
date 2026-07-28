// Compiles to stack.compose.yaml and stack.services.yaml — do not edit the YAML.
// No secrets — no env_file needed.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'mazanoke';
local version = 'v1.1.5';
local port = 80;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/civilblur/mazanoke:' + version,
      expose: [std.toString(port)],
      ports: ['%s:18008:%s' % [reg.ips.loopback, port]],
    },
  }),
)
