// The one stack that cannot read its own secrets through the infisical-secrets provider:
// the provider would be asking this server for them before it is up. Its secrets stay an
// env file the control plane writes, spelled out here because nothing else reads it —
// ANSIBLE_SECRETS_FILE overrides the path during bootstrap.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'infisical',
  envFiles:: ['${ANSIBLE_SECRETS_FILE:-%s/infisical.env}' % lib.collections.dirs.secrets],

  app:: self.Service { role:: lib.collections.role.APP },
  db:: self.Service { role:: lib.collections.role.DB },
  // `redis` rather than lib.collections.role.CACHE: the container name is what other things
  // on the host already know it by.
  redis:: self.Service { role:: 'redis' },

  dbData:: self.Volume { key:: 'db' },
  redisData:: self.Volume { key:: 'redis' },
};

local appVersion = 'v0.160.9';
local dbVersion = '16-alpine';
local redisVersion = '7-alpine';

local infisical = lib.registry.endpoint.serviceGroup.infisical;
local appPort = infisical.container.port;
local dbUser = refs.name;
local dbName = refs.name;

local gateway = lib.registry.network.shared.tailscale_gw_001;

{
  // Two documents, because env_file has to attach at the include: `${VAR:-}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [gateway.name]: { name: gateway.name, external: true },
    },
    volumes: refs.dbData.declare + refs.redisData.declare,

    services: {
      [refs.app.key]: {
        // infisical-app is registry.endpoint.infisical.container.name — other stacks dial it.
        container_name: infisical.container.name,
        image: 'docker.io/infisical/infisical:' + appVersion,
        restart: lib.collections.restart.unlessStopped,
        networks: ['default', gateway.name],
        depends_on: {
          [refs.db.key]: { condition: lib.collections.condition.healthy },
          [refs.redis.key]: { condition: lib.collections.condition.healthy },
        },
        environment: {
          SITE_URL: infisical.proxy.url,
          SMTP_HOST: '${INFISICAL__SMTP_HOST:-}',
          SMTP_PORT: '${INFISICAL__SMTP_PORT:-}',
          SMTP_FROM_ADDRESS: '${INFISICAL__SMTP_FROM_ADDRESS:-}',
          SMTP_FROM_NAME: '${INFISICAL__SMTP_FROM_NAME:-}',
          NODE_ENV: 'production',
          REDIS_URL: 'redis://%s:6379' % refs.redis.key,
          ENCRYPTION_KEY: '${INFISICAL_ENCRYPTION_KEY:-}',
          AUTH_SECRET: '${INFISICAL_AUTH_SECRET:-}',
          DB_CONNECTION_URI: 'postgres://%s:${INFISICAL_DB_PASSWORD:-}@%s:5432/%s'
                             % [dbUser, refs.db.key, dbName],
          SMTP_USERNAME: '${INFISICAL__SMTP_USERNAME:-}',
          SMTP_PASSWORD: '${INFISICAL_SMTP_PASSWORD:-}',
        },
        healthcheck: {
          test: ['CMD', 'curl', '-f', 'http://localhost:%s/api/status' % appPort],
          interval: '30s',
          timeout: '10s',
          retries: 3,
          start_period: '40s',
        },
        expose: [appPort],
        ports: [
          '%s:%s:%s' % [ lib.collections.ip.loopback, infisical.host.port, appPort],
          '%s:%s:%s' % [ infisical.host.on.tailscaleIP , infisical.host.port, appPort],
          ],
      },

      [refs.db.key]: {
        container_name: refs.db.ext,
        image: 'docker.io/library/postgres:' + dbVersion,
        restart: lib.collections.restart.unlessStopped,
        networks: ['default', gateway.name],
        volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
          POSTGRES_PASSWORD: '${INFISICAL_DB_PASSWORD:-}',
        },
        healthcheck: {
          test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
          interval: '5s',
          timeout: '10s',
          retries: 10,
        },
        expose: ['5432'],
        ports: ['%s:18042:5432' % lib.collections.ip.loopback],
      },

      [refs.redis.key]: {
        container_name: refs.redis.ext,
        image: 'docker.io/library/redis:' + redisVersion,
        restart: lib.collections.restart.unlessStopped,
        volumes: [refs.redisData.mount('/data')],
        environment: {
          ALLOW_EMPTY_PASSWORD: 'yes',
        },
        healthcheck: {
          test: ['CMD', 'redis-cli', 'ping'],
          interval: '10s',
          timeout: '5s',
          retries: 5,
        },
        expose: ['6379'],
      },
    },
  },
}
