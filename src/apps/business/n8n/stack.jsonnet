// Compiles to compose.yaml and stack.services.yaml — do not edit the YAML.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'n8n';
local pg = reg.endpoint.postgres.host;

local version = '2.20.6';
local port = 5678;
local timezone = 'America/New_York';

local bindRoot = reg.dirs.docker.root + reg.dirs.docker.bindMounts + '/apps/n8n/data';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'docker.n8n.io/n8nio/n8n:' + version,
      // Do NOT set user: "0:0" — n8n would write to /root/.n8n in the
      // container's writable layer instead of this bind mount, wiping data
      // on every redeploy. Host dir is owned by UID 1000 (image default).
      mounts_:: [
        bindRoot + '/.n8n:/home/node/.n8n',
        bindRoot + '/local-files:/files',
      ],
      environment: {
        GENERIC_TIMEZONE: timezone,
        TZ: timezone,
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: 'true',
        N8N_PORT: std.toString(port),
        N8N_PROTOCOL: 'https',
        N8N_RUNNERS_ENABLED: 'true',
        NODE_ENV: 'production',
        N8N_PROXY_HOPS: '1',
        N8N_BLOCK_ENV_ACCESS_IN_NODE: 'true',
        N8N_GIT_NODE_DISABLE_BARE_REPOS: 'true',
        WEBHOOK_URL: 'https://' + name + '.' + reg.domains.ktbinternal + '/',
        N8N_HOST: name + '.' + reg.domains.ktbinternal,
        DB_TYPE: 'postgresdb',
        DB_POSTGRESDB_HOST: pg.host,
        DB_POSTGRESDB_PORT: pg.port,
        DB_POSTGRESDB_DATABASE: name,
        DB_POSTGRESDB_SCHEMA: 'public',
        DB_POSTGRESDB_USER: '${POSTGRES_USER:?err}',
        DB_POSTGRESDB_PASSWORD: '${POSTGRES_PASS:?err}',
      },
      dns: ['192.168.1.6', '1.1.1.1'],
      expose: [std.toString(port)],
      extra_hosts: ['host.docker.internal:host-gateway'],
      ports: ['%s:5678:%s' % [reg.ips.loopback, port]],
    },
  }),
  [lib.Secret('postgres')],
)
