// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
// Grist — self-hosted spreadsheet/database, single container, reached via exposed port.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'grist';
local version = '1.7.16';
local port = 8484;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'gristlabs/grist:' + version,
      volumes_:: { app: '/persist' },
      environment: {
        APP_HOME_URL:                   'https://' + name + '.' + reg.domains.ktbinternal,
        // Enable later for data backup to NAS
        // GRIST_DOCS_MINIO_BUCKET:        my-grist-docs,
        // GRIST_DOCS_MINIO_ENDPOINT:      s3.amazonaws.com,
        // GRIST_DOCS_MINIO_ACCESS_KEY:    '',
        // GRIST_DOCS_MINIO_SECRET_KEY:    '',
        // Stable across restarts so sessions survive — set in Infisical before first up.
        // GRIST_SESSION_SECRET: '${GRIST_SESSION_SECRET:?err}',
      },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:' + std.toString(port) + '/status'],
        interval: '30s',
        timeout: '10s',
        retries: 5,
      },
      expose: [std.toString(port)],
      ports: ['%s:18017:%s' % [reg.ips.loopback, port]],
    },
  }),
)
