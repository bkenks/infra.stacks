// infisical — the secrets store itself. Bootstrapped by Ansible (it cannot read its own
// secrets through the agent before it exists), which is why render() takes
// SecretOrBootstrap rather than Secret.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'infisical';

// `redis` is not in reg.role (role.CACHE would rename the container to infisical_cache),
// and the container name is what other things on the host already know it by.
local redis = 'redis';

local appVersion = 'v0.160.9';
local dbVersion = '16-alpine';
local redisVersion = '7-alpine';

local appPort = 8080;  // matches reg.endpoint.infisical.container.port
local dbUser = 'infisical';
local dbName = 'infisical';

lib.render(
  name,

  lib.Stack(
    name,
    function(ref) {
      // container_name lands on infisical_app, which is reg.endpoint.infisical.container.host.
      [role.APP]: lib.Service {
        image: 'docker.io/infisical/infisical:' + appVersion,
        depends_on: {
          [role.DB]: { condition: 'service_healthy' },
          [redis]: { condition: 'service_healthy' },
        },
        environment: {
          SITE_URL: reg.endpoint.infisical.public.url,

          // Optional; blank disables email.
          SMTP_HOST: '${INFISICAL__SMTP_HOST:-}',
          SMTP_PORT: '${INFISICAL__SMTP_PORT:-}',
          SMTP_FROM_ADDRESS: '${INFISICAL__SMTP_FROM_ADDRESS:-}',
          SMTP_FROM_NAME: '${INFISICAL__SMTP_FROM_NAME:-}',

          NODE_ENV: 'production',

          REDIS_URL: 'redis://' + ref[redis] + ':6379',

          // Ansible-rendered into platform.env, so infisical can read its own secrets despite being the server.
          ENCRYPTION_KEY: '${INFISICAL_ENCRYPTION_KEY:?err}',
          AUTH_SECRET: '${INFISICAL_AUTH_SECRET:?err}',
          DB_CONNECTION_URI: 'postgres://' + dbUser + ':${INFISICAL_DB_PASSWORD:?err}@' + ref[role.DB] + ':5432/' + dbName,
          SMTP_USERNAME: '${INFISICAL__SMTP_USERNAME:-}',
          SMTP_PASSWORD: '${INFISICAL_SMTP_PASSWORD:-}',
        },
        healthcheck: {
          test: ['CMD', 'curl', '-f', 'http://localhost:' + std.toString(appPort) + '/api/status'],
          interval: '30s',
          timeout: '10s',
          retries: 3,
          start_period: '40s',
        },
        expose: [appPort],
        // CURRENT INTENDED VALUE — this is the in-progress port edit, not what the
        // deployed compose.stack.yaml still carries. The publish is now loopback-only:
        // the tailnet, LAN and 172.28.0.1 gateway bindings were dropped, so the UI/API is
        // reached through the edge proxy rather than direct on those addresses.
        ports: [reg.endpoint.infisical.host.port + ":" + appPort],
      },

      [role.DB]: lib.Service {
        image: 'docker.io/library/postgres:' + dbVersion,
        volumes_:: { db: '/var/lib/postgresql/data' },
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
          // Same source as the app's INFISICAL_DB_PASSWORD.
          POSTGRES_PASSWORD: '${INFISICAL_DB_PASSWORD:?err}',
        },
        healthcheck: {
          test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
          interval: '5s',
          timeout: '10s',
          retries: 10,
        },
        expose: ['5432'],
      },

      [redis]: lib.Service {
        image: 'docker.io/library/redis:' + redisVersion,
        volumes_:: { redis: '/data' },
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

    // A second network on top of the private default: the 172.28.0.0/24 bridge whose
    // gateway other stacks dial as the host gateway.
    { default: { name: name } } + reg.networks.hostGateway.create(name),
  ),

  [lib.SecretOrBootstrap('infisical')],
)
