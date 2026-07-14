// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
// Grist — self-hosted spreadsheet/database, single container, reached via exposed port.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'grist';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

local version = '1.7.16';
local port = 8484;

local manifest = {
  name: stack,

  services: {
    [app]: {
      image: 'gristlabs/grist:' + version,
      container_name: n.container(app),
      volumes: [n.volume(app) + ':/persist'],
      environment: {
        APP_HOME_URL:                   'https://' + stack + '.' + reg.domains.ktbinternal,
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
      networks: {
        default: { aliases: [n.container(app)] },
      },
    } + c.publish(18017, port),
  },

  volumes: {
    [n.volume(app)]: { name: n.volume(app) },
  },

  networks:
    s.network.default,
};

c.render(stack, manifest)
