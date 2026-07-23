// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'stirling-pdf';
local version = '2.10.1';
local port = 8080;

local base = reg.dirs.docker.root + reg.dirs.docker.bindMounts + '/apps/stirling-pdf';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'stirlingtools/stirling-pdf:' + version,
      mounts_:: [
        base + '/configs:/configs',
        base + '/tessdata:/usr/share/tessdata',
        base + '/logs:/logs',
        base + '/pipeline:/pipeline',
      ],
      environment: {
        SECURITY_ENABLELOGIN: 'true',
        LANGS: 'en_US',
        // Default login is admin/stirling. To change it, set
        // SECURITY_INITIALLOGIN_USERNAME / SECURITY_INITIALLOGIN_PASSWORD.
      },
      expose: [std.toString(port)],
      ports: ['%s:18012:%s' % [reg.ips.loopback, port]],
    },
  }),
)
