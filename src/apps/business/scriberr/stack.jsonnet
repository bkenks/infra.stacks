// Compiles to stack.compose.yaml and stack.services.yaml — do not edit the YAML.
// No secrets: nothing is rendered to /dev/shm for this stack.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'scriberr';
local port = 8080;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      // Pinned by digest (upstream has no stable version tags) — do not
      // replace with a floating tag.
      image: 'ghcr.io/rishikanthc/scriberr@sha256:9e36448fb5a6003b28cd3d9ac783e8cbef5ed916936c20ec353a55fa380484f4',
      // app owns two volumes, so each key is suffixed with its purpose
      // (<role>_<purpose>) instead of the bare role.
      volumes_:: {
        app_data: '/app/data',
        'app_whisperx-env': '/app/whisperx-env',
      },
      environment: {
        APP_ENV: 'production',
        PUID: '1000',
        PGID: '1000',
        ALLOWED_ORIGINS: 'https://' + name + '.' + reg.domains.ktbinternal,
      },
      expose: [std.toString(port)],
      ports: ['%s:18011:%s' % [reg.ips.loopback, port]],
    },
  }),
)
