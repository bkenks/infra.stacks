// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'twenty';
local s = c.stack(stack);
local n = s.names;
local redis = reg.roles.redis;
local server = 'server';
local worker = 'worker';

local pgHost = reg.endpoints.postgres.container.host;  // 'postgres_db'
local pgPort = reg.endpoints.postgres.container.port;  // 5432
local dbName = 'twenty';

local imageVersion = 'v1.18.1';
local redisVersion = '8.6.1';

local serverPort = 3000;
local serverUrl = 'https://' + stack + '.' + reg.domains.ktbinternal;

local commonEnv = {
  PG_DATABASE_URL: 'postgres://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + std.toString(pgPort) + '/' + dbName,

  APP_SECRET: '${TWENTY_SECRET:?err}',
  AUTH_GOOGLE_CLIENT_ID: '${TWENTY_GOOGLE_CLIENT_ID:?err}',
  AUTH_GOOGLE_CLIENT_SECRET: '${TWENTY_GOOGLE_CLIENT_SECRET:?err}',

  REDIS_URL: 'redis://' + n.container(redis) + ':6379',
  SERVER_URL: serverUrl,
  AUTH_GOOGLE_CALLBACK_URL: serverUrl + '/auth/google/redirect',
  AUTH_GOOGLE_APIS_CALLBACK_URL: serverUrl + '/auth/google-apis/get-access-token',
  STORAGE_TYPE: 'local',
  MESSAGING_PROVIDER_GMAIL_ENABLED: 'true',
  CALENDAR_PROVIDER_GOOGLE_ENABLED: 'true',
};

local manifest = {
  name: stack,

  services: {
    [redis]: {
      image: 'docker.io/library/redis:' + redisVersion,
      container_name: n.container(redis),
      command: ['--maxmemory-policy', 'noeviction'],
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD', 'redis-cli', 'ping'],
        interval: '5s',
        timeout: '5s',
        retries: 10,
      },
      networks: { default: { aliases: [n.container(redis)] } },
      expose: ['6379'],
    },

    [server]: {
      image: 'docker.io/twentycrm/twenty:' + imageVersion,
      container_name: n.container(server),
      depends_on: { [redis]: { condition: 'service_healthy' } },
      volumes: [n.volume('server-storage') + ':/app/packages/twenty-server/.local-storage'],
      environment: commonEnv { NODE_PORT: std.toString(serverPort) },
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD', 'curl', '--fail', 'http://localhost:' + std.toString(serverPort) + '/healthz'],
        interval: '5s',
        timeout: '5s',
        retries: 20,
      },
      expose: [std.toString(serverPort)],
      networks: {
        default: { aliases: [n.container(server)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(server)] },
        [reg.sharedNetworks.postgres.name]: { aliases: [n.container(server)] },
      },
      labels: s.proxy.add(stack, stack, serverPort),
    } + c.publish(18015, serverPort),

    [worker]: {
      image: 'docker.io/twentycrm/twenty:' + imageVersion,
      container_name: n.container(worker),
      depends_on: { [server]: { condition: 'service_healthy' } },
      volumes: [n.volume('server-storage') + ':/app/packages/twenty-server/.local-storage'],
      environment: commonEnv {
        // Migrations + cron registration already run on the server; running
        // them again here would race/duplicate.
        DISABLE_DB_MIGRATIONS: 'true',
        DISABLE_CRON_JOBS_REGISTRATION: 'true',
      },
      command: ['yarn', 'worker:prod'],
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.container(worker)] },
        [reg.sharedNetworks.postgres.name]: { aliases: [n.container(worker)] },
      },
    },
  },

  volumes: {
    [n.volume('server-storage')]: { name: n.volume('server-storage') },
  },

  networks:
    s.network.default
    + s.network.join(reg.sharedNetworks.proxy)
    + s.network.join(reg.sharedNetworks.postgres),
};

c.render(stack, manifest, [secrets.twenty.path, secrets.postgres.path])
