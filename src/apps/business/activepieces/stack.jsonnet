// activepieces: one image run two ways — the API/UI `app` and a pool of flow `worker`s —
// over a dedicated pgvector Postgres and a Redis queue.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'activepieces',

  app:: self.Service { role:: lib.collections.role.APP },
  worker:: self.Service { role:: lib.collections.role.WORKER },
  db:: self.Service { role:: lib.collections.role.DB },
  cache:: self.Service { role:: lib.collections.role.CACHE },

  dbData:: self.Volume { key:: 'db' },
  cacheData:: self.Volume { key:: 'cache' },
  // Piece/engine cache, shared by app and every worker replica.
  engineCache:: self.Volume { key:: 'engine' },
};

local appVersion = '0.88.3';
local dbVersion = '0.8.0-pg14';
local cacheVersion = '7.0.7';

local appPort = '80';
local dbPort = '5432';
local cachePort = '6379';
local workerReplicas = 5;
local dbUser = 'postgres';
local dbName = refs.name;

local image = 'ghcr.io/activepieces/activepieces:' + appVersion;
local engineCachePath = '/usr/src/app/cache';

// Shared by app and worker. AP_POSTGRES_PASSWORD, AP_ENCRYPTION_KEY and AP_JWT_SECRET
// arrive from infisical-secrets.
local apEnv = {
  AP_ENVIRONMENT: 'prod',
  AP_EDITION: 'ee',
  AP_FRONTEND_URL: 'https://%s.%s' % [refs.name, lib.collections.domain.ktbinternal],
  AP_ENGINE_EXECUTABLE_PATH: 'dist/packages/engine/main.js',
  AP_EXECUTION_MODE: 'SANDBOX_CODE_ONLY',
  AP_WEBHOOK_TIMEOUT_SECONDS: '30',
  AP_FLOW_TIMEOUT_SECONDS: '600',
  AP_TRIGGER_DEFAULT_POLL_INTERVAL: '5',
  AP_TELEMETRY_ENABLED: 'true',
  AP_TEMPLATES_SOURCE_URL: 'https://cloud.activepieces.com/api/v1/flow-templates',
  AP_TOOL_SEARCH_ENABLED: 'false',

  AP_POSTGRES_HOST: refs.db.key,
  AP_POSTGRES_PORT: dbPort,
  AP_POSTGRES_DATABASE: dbName,
  AP_POSTGRES_USERNAME: dbUser,
  AP_REDIS_HOST: refs.cache.key,
  AP_REDIS_PORT: cachePort,
};

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.dbData.declare + refs.cacheData.declare + refs.engineCache.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('apps', '/activepieces'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: image,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady {
          [refs.db.key]: { condition: lib.collections.condition.healthy },
          [refs.cache.key]: { condition: lib.collections.condition.healthy },
        },
        volumes: [refs.engineCache.mount(engineCachePath)],
        environment: apEnv {
          AP_CONTAINER_TYPE: 'APP',
        },
        expose: [appPort],
        ports: ['%s:18071:%s' % [lib.collections.ip.loopback, appPort]],
      },

      // No container_name: compose refuses a fixed name on a replicated service.
      [refs.worker.key]: {
        image: image,
        restart: lib.collections.restart.onFailure(5),
        deploy: { replicas: workerReplicas },
        depends_on: lib.secretsReady {
          [refs.app.key]: { condition: lib.collections.condition.started },
        },
        volumes: [refs.engineCache.mount(engineCachePath)],
        environment: apEnv {
          AP_CONTAINER_TYPE: 'WORKER',
          // Workers reach the API over the private bridge, not the public URL.
          AP_FRONTEND_URL: 'http://' + refs.app.key,
        },
      },

      // Dedicated pgvector Postgres — activepieces needs the vector extension, which the
      // shared cluster does not carry. POSTGRES_PASSWORD arrives from infisical-secrets.
      [refs.db.key]: {
        container_name: refs.db.ext,
        image: 'docker.io/pgvector/pgvector:' + dbVersion,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
        },
        healthcheck: {
          test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
          interval: '5s',
          timeout: '10s',
          retries: 10,
        },
        expose: [dbPort],
      },

      [refs.cache.key]: {
        container_name: refs.cache.ext,
        image: 'docker.io/library/redis:' + cacheVersion,
        restart: lib.collections.restart.onFailure(5),
        volumes: [refs.cacheData.mount('/data')],
        healthcheck: {
          test: ['CMD', 'redis-cli', 'ping'],
          interval: '10s',
          timeout: '5s',
          retries: 5,
        },
        expose: [cachePort],
      },
    },
  },
}
