// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'twenty';
// Twenty's own config dials the cache as `redis`, so the key stays a literal rather
// than role.CACHE.
local redis = 'redis';

local pgHost = reg.endpoint.postgres.host.host;  // 'host.docker.internal'
local pgPort = reg.endpoint.postgres.host.port;  // '6109'
local dbName = 'twenty';

local imageVersion = 'v1.18.1';
local redisVersion = '8.6.1';

local serverPort = 3000;
local serverUrl = 'https://' + name + '.' + reg.domains.ktbinternal;

// Shared by server and worker. Takes the redis name from `ref` so the cache it dials
// can never drift from the service this stack actually declares.
local commonEnv(redisHost) = {
  PG_DATABASE_URL: 'postgres://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + pgPort + '/' + dbName,

  APP_SECRET: '${TWENTY_SECRET:?err}',
  // AUTH_GOOGLE_CLIENT_ID: '${TWENTY_GOOGLE_CLIENT_ID:?err}',
  // AUTH_GOOGLE_CLIENT_SECRET: '${TWENTY_GOOGLE_CLIENT_SECRET:?err}',

  REDIS_URL: 'redis://' + redisHost + ':6379',
  SERVER_URL: serverUrl,
  // AUTH_GOOGLE_CALLBACK_URL: serverUrl + '/auth/google/redirect',
  // AUTH_GOOGLE_APIS_CALLBACK_URL: serverUrl + '/auth/google-apis/get-access-token',
  STORAGE_TYPE: 'local',
  // MESSAGING_PROVIDER_GMAIL_ENABLED: 'true',
  // CALENDAR_PROVIDER_GOOGLE_ENABLED: 'true',
};

// Mounted by both server and worker; Stack() collapses the two declarations into the
// one top-level twenty_server-storage volume.
local storage = { 'server-storage': '/app/packages/twenty-server/.local-storage' };

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [redis]: lib.Service {
      image: 'docker.io/library/redis:' + redisVersion,
      command: ['--maxmemory-policy', 'noeviction'],
      healthcheck: {
        test: ['CMD', 'redis-cli', 'ping'],
        interval: '5s',
        timeout: '5s',
        retries: 10,
      },
      expose: ['6379'],
    },

    [role.SERVER]: lib.Service {
      image: 'docker.io/twentycrm/twenty:' + imageVersion,
      depends_on: { [redis]: { condition: 'service_healthy' } },
      volumes_:: storage,
      environment: commonEnv(ref[redis]) { NODE_PORT: std.toString(serverPort) },
      healthcheck: {
        test: ['CMD', 'curl', '--fail', 'http://localhost:' + std.toString(serverPort) + '/healthz'],
        interval: '5s',
        timeout: '5s',
        retries: 20,
      },
      expose: [std.toString(serverPort)],
      ports: ['%s:18015:%s' % [reg.ips.loopback, serverPort]],
      // Shared Postgres is reached over the docker host-gateway — there are no shared
      // Docker networks.
      extra_hosts: ['host.docker.internal:host-gateway'],
    },

    [role.WORKER]: lib.Service {
      image: 'docker.io/twentycrm/twenty:' + imageVersion,
      depends_on: { [role.SERVER]: { condition: 'service_healthy' } },
      volumes_:: storage,
      environment: commonEnv(ref[redis]) {
        // Migrations + cron registration already run on the server; running
        // them again here would race/duplicate.
        DISABLE_DB_MIGRATIONS: 'true',
        DISABLE_CRON_JOBS_REGISTRATION: 'true',
      },
      command: ['yarn', 'worker:prod'],
      extra_hosts: ['host.docker.internal:host-gateway'],
    },
  },
  ),
  [lib.Secret('twenty'), lib.Secret('postgres')],
)
