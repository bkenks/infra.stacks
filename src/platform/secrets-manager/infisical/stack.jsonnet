local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'infisical',
  // The server is bootstrapped by Ansible — it cannot read its own secrets through the
  // agent before the agent exists.
  envFiles:: [lib.SecretOrBootstrap('infisical')],

  app:: self.Service { role:: lib.collections.role.APP },
  db:: self.Service { role:: lib.collections.role.DB },
  // `redis` rather than lib.collections.role.CACHE: the container name is what other things on the
  // host already know it by.
  redis:: self.Service { role:: 'redis' },
  agent:: self.Service { role:: lib.collections.role.AGENT },

  dbData:: self.Volume { key:: 'db' },
  redisData:: self.Volume { key:: 'redis' },
};

local serverProfile = 'server';

local appVersion = 'v0.160.9';
local dbVersion = '16-alpine';
local redisVersion = '7-alpine';

local infisical = lib.registry.endpoint.serviceGroup.infisical;
local appPort = infisical.container.port;
local dbUser = refs.name;
local dbName = refs.name;

local sharedDB = lib.registry.network.shared.infisicalDB;
local gateway = lib.registry.network.shared.tsGateway;

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [sharedDB.name]: { name: sharedDB.name, external: true },
      [gateway.name]: { name: gateway.name, external: true },
    },
    volumes: refs.dbData.declare + refs.redisData.declare,

    services: {
      [refs.app.key]: {
        // infisical_app is registry.endpoint.infisical.container.name — other stacks dial it.
        container_name: infisical.container.name,
        profiles: [serverProfile],
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
        profiles: [serverProfile],
        image: 'docker.io/library/postgres:' + dbVersion,
        restart: lib.collections.restart.unlessStopped,
        networks: ['default', sharedDB.name],
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
        profiles: [serverProfile],
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

      // [refs.agent.key]: {
      //   container_name: refs.agent.ext,
      //   profiles: [agentProfile],
      //   image: 'docker.io/infisical/cli:' + agentVersion,
      //   restart: lib.collections.restart.unlessStopped,
      //   entrypoint: ['/bin/sh', '/agent/entrypoint.sh'],
      //   volumes: [
      //     './files/entrypoint.sh:/agent/entrypoint.sh:ro',
      //     // Per-service agent config fragments.
      //     './templates:/agent/templates:ro',
      //     // Read creds and write the rendered <stack>.env files.
      //     '%s:%s' % [lib.collections.dirs.secrets, lib.collections.dirs.secrets],
      //   ],
      //   // Empty defaults, not `:?err`: compose interpolates this service even when the agent
      //   // profile is off, so a required var would break server-only bootstrap. With the
      //   // profile on, a missing credential surfaces as an agent auth failure the healthcheck
      //   // flips to unhealthy.
      //   environment: {
      //     // Per-host: drives the ${AGENT_HOST} substitutions in the secret paths.
      //     AGENT_HOST: '${AGENT_HOST:-}',
      //     // Per-host: which templates/ fragments to render.
      //     AGENT_SERVICES: '${AGENT_SERVICES:-}',
      //     INFISICAL_CLIENT_ID: '${INFISICAL_CLIENT_ID:-}',
      //     INFISICAL_CLIENT_SECRET: '${INFISICAL_CLIENT_SECRET:-}',
      //     // The in-cluster address by default; a per-host override is allowed.
      //     INFISICAL_ADDRESS: '${INFISICAL_ADDRESS:-%s}' % infisical.container.url(),
      //   },
      //   healthcheck: {
      //     test: ['CMD-SHELL', '[ ! -f /tmp/agent.last_err ] || [ $$(( $$(date +%s) - $$(cat /tmp/agent.last_err) )) -ge 180 ]'],
      //     interval: '30s',
      //     timeout: '5s',
      //     retries: 2,
      //     start_period: '30s',
      //   },
      // },
    },
  },
}
