local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'infisical';
local s = c.stack(stack);
local n = s.names;
local roles = reg.roles;

local appVersion = 'v0.160.9';
local dbVersion = '16-alpine';
local redisVersion = '7-alpine';

local appPort = 8080;  // matches reg.endpoints.infisical.container.port
local dbUser = 'infisical';
local dbName = 'infisical';

// Host port for the proxy-bypass publish. Bound to loopback and to the tailnet address of
// the host infisical runs on, so the UI/API is reachable over Tailscale without Traefik.
local hostPort = 18006;
local tsIp = reg.server.hosts.littlebuddy.ip;

local manifest = {
  name: stack,

  services: {
    [roles.app]: {
      image: 'docker.io/infisical/infisical:' + appVersion,
      container_name: n.container(roles.app),  // matches reg.endpoints host
      depends_on: {
        db: { condition: 'service_healthy' },
        redis: { condition: 'service_healthy' },
      },
      environment: {
        SITE_URL: c.url(reg.endpoints.infisical).public,

        // Optional; blank disables email.
        SMTP_HOST: '${INFISICAL__SMTP_HOST:-}',
        SMTP_PORT: '${INFISICAL__SMTP_PORT:-}',
        SMTP_FROM_ADDRESS: '${INFISICAL__SMTP_FROM_ADDRESS:-}',
        SMTP_FROM_NAME: '${INFISICAL__SMTP_FROM_NAME:-}',

        NODE_ENV: 'production',

        REDIS_URL: 'redis://' + n.container(roles.redis) + ':6379',

        // Ansible-rendered into platform.env, so infisical can read its own secrets despite being the server.
        ENCRYPTION_KEY: '${INFISICAL_ENCRYPTION_KEY:?err}',
        AUTH_SECRET: '${INFISICAL_AUTH_SECRET:?err}',
        DB_CONNECTION_URI: 'postgres://' + dbUser + ':${INFISICAL_DB_PASSWORD:?err}@' + n.container(roles.db) + ':5432/' + dbName,
        SMTP_USERNAME: '${INFISICAL__SMTP_USERNAME:-}',
        SMTP_PASSWORD: '${INFISICAL_SMTP_PASSWORD:-}',
      },
      networks: {
        default: { aliases: [n.container(roles.app)] },
      },
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD', 'curl', '-f', 'http://localhost:' + std.toString(appPort) + '/api/status'],
        interval: '30s',
        timeout: '10s',
        retries: 3,
        start_period: '40s',
      },
      expose: [std.toString(appPort)],
    } + c.publish(hostPort, appPort)
      + { ports+: [tsIp + ':' + std.toString(hostPort) + ':' + std.toString(appPort)] },

    [roles.db]: {
      image: 'docker.io/library/postgres:' + dbVersion,
      container_name: n.container(roles.db),
      volumes: [roles.db + ':/var/lib/postgresql/data'],
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        // Same source as the app's INFISICAL_DB_PASSWORD.
        POSTGRES_PASSWORD: '${INFISICAL_DB_PASSWORD:?err}',
      },
      networks: {
        default: { aliases: [n.container(roles.db)] },
      },
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
        interval: '5s',
        timeout: '10s',
        retries: 10,
      },
      expose: ['5432'],
    },

    [roles.redis]: {
      image: 'docker.io/library/redis:' + redisVersion,
      container_name: n.container(roles.redis),
      volumes: [roles.redis + ':/data'],
      environment: {
        ALLOW_EMPTY_PASSWORD: 'yes',
      },
      networks: {
        default: { aliases: [n.container(roles.redis)] },
      },
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD', 'redis-cli', 'ping'],
        interval: '10s',
        timeout: '5s',
        retries: 5,
      },
      expose: ['6379'],
    },
  },

  networks:
    s.network.default,

  volumes: {
    [roles.db]: { name: n.volume(roles.db) },
    [roles.redis]: { name: n.volume(roles.redis) },
  },
};

c.render(stack, manifest, [secrets.infisical.platformPath])
