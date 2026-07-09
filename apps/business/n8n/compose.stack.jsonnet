// Compiles to compose.stack.yaml — do not edit the YAML.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'n8n';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;
local pgHost = reg.endpoints.postgres.container.host;  // 'postgres_db'
local pgPort = reg.endpoints.postgres.container.port;  // 5432

local version = '2.20.6';
local port = 5678;
local timezone = 'America/New_York';

local dataDir = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/n8n/data/.n8n';
local filesDir = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/n8n/data/local-files';

{
  name: stack,

  services: {
    [app]: {
      image: 'docker.n8n.io/n8nio/n8n:' + version,
      container_name: n.container(app),
      // Do NOT set user: "0:0" — n8n would write to /root/.n8n in the
      // container's writable layer instead of this bind mount, wiping data
      // on every redeploy. Host dir is owned by UID 1000 (image default).
      volumes: [
        dataDir + ':/home/node/.n8n',
        filesDir + ':/files',
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
        WEBHOOK_URL: 'https://' + stack + '.' + reg.domains.ktbinternal + '/',
        N8N_HOST: stack + '.' + reg.domains.ktbinternal,
        DB_TYPE: 'postgresdb',
        DB_POSTGRESDB_HOST: pgHost,
        DB_POSTGRESDB_PORT: std.toString(pgPort),
        DB_POSTGRESDB_DATABASE: stack,
        DB_POSTGRESDB_SCHEMA: 'public',
        DB_POSTGRESDB_USER: '${POSTGRES_USER:?err}',
        DB_POSTGRESDB_PASSWORD: '${POSTGRES_PASS:?err}',
      },
      restart: 'unless-stopped',
      dns: ['192.168.1.6', '1.1.1.1'],
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
        [reg.sharedNetworks.postgres.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add(stack, stack, port),
    },
  },

  networks:
    s.network.default
    + s.network.join('proxy')
    + s.network.join('postgres'),
}
