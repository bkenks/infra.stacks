// infisical — the secrets store itself, plus the agent that renders every host's secrets.
// Split into `server` and `agent` Compose profiles (see the profile note below). The server
// is bootstrapped by Ansible (it cannot read its own secrets through the agent before it
// exists), which is why render() takes SecretOrBootstrap rather than Secret.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'infisical';

// `redis` is not in reg.role (role.CACHE would rename the container to infisical_cache),
// and the container name is what other things on the host already know it by.
local redis = 'redis';

// Two profiles carve one file into two deployment shapes. The server (app/db/redis)
// runs on the single Infisical host; the agent runs on every host, rendering that host's
// secrets. Nothing runs without a profile:
//   littlebuddy (server host):  COMPOSE_PROFILES=server,agent
//   every other host:           COMPOSE_PROFILES=agent
//   Ansible bootstrap:          COMPOSE_PROFILES=server
//
// Compose interpolates the WHOLE file on every host regardless of the active profile, so
// no var here can use `:?err`: an agent-only host has no server secrets and a server-only
// bootstrap has no agent creds, yet both would still be interpolated. Every var therefore
// carries an empty default and validation moves to runtime — the Infisical app rejects an
// empty ENCRYPTION_KEY at boot, and the agent's entrypoint.sh does `:?` checks of its own.
local serverProfile = 'server';
local agentProfile = 'agent';

local appVersion = 'v0.160.9';
local dbVersion = '16-alpine';
local redisVersion = '7-alpine';
local agentVersion = '0.43.89';

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
        profiles: [serverProfile],
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

          // Ansible-rendered into platform.env, so infisical can read its own secrets despite
          // being the server. Empty default (not `:?err`) — see the whole-file interpolation
          // note above; the app rejects an empty ENCRYPTION_KEY at boot.
          ENCRYPTION_KEY: '${INFISICAL_ENCRYPTION_KEY:-}',
          AUTH_SECRET: '${INFISICAL_AUTH_SECRET:-}',
          DB_CONNECTION_URI: 'postgres://' + dbUser + ':${INFISICAL_DB_PASSWORD:-}@' + ref[role.DB] + ':5432/' + dbName,
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
        // Loopback-bound like every other host port: the public entrypoint is
        // reg.endpoint.infisical.public.url via the edge proxy, not this mapping.
        // Without the prefix this publishes on 0.0.0.0, which reaches the
        // internet on a public-IP host because Docker's iptables rules bypass ufw.
        ports: [reg.ips.loopback + ":" + reg.endpoint.infisical.host.port + ":" + appPort],
      },

      [role.DB]: lib.Service {
        profiles: [serverProfile],
        image: 'docker.io/library/postgres:' + dbVersion,
        volumes_:: { db: '/var/lib/postgresql/data' },
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
          // Same source as the app's INFISICAL_DB_PASSWORD; empty default per the interpolation
          // note above, and postgres refuses to initialize on an empty password anyway.
          POSTGRES_PASSWORD: '${INFISICAL_DB_PASSWORD:-}',
        },
        healthcheck: {
          test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
          interval: '5s',
          timeout: '10s',
          retries: 10,
        },
        expose: ['5432'],
        ports: [reg.ips.loopback + ":18042:5432"],
        networks_:: lib.network.join(reg.networks.shared.infisicalDB),
      },

      [redis]: lib.Service {
        profiles: [serverProfile],
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

      [role.AGENT]: lib.Service {
        profiles: [agentProfile],
        image: 'docker.io/infisical/cli:' + agentVersion,
        entrypoint: ['/bin/sh', '/agent/entrypoint.sh'],
        mounts_:: [
          './files/entrypoint.sh:/agent/entrypoint.sh:ro',
          './templates:/agent/templates:ro',     // per-service config fragments, generated from registry
          '/dev/shm:/dev/shm',                   // read creds + write rendered <stack>.env files
        ],
        // Empty defaults, not `:?err`: Compose interpolates this service even when the
        // agent profile is off, so a required var would break server-only bootstrap. When
        // the profile is on, a missing credential surfaces as an agent auth failure the
        // healthcheck flips to unhealthy.
        environment: {
          AGENT_HOST: '${AGENT_HOST:-}',          // per-host: drives ${AGENT_HOST} secret-path subs
          AGENT_SERVICES: '${AGENT_SERVICES:-}',  // per-host: which templates/ fragments to render
          INFISICAL_CLIENT_ID: '${INFISICAL_CLIENT_ID:-}',
          INFISICAL_CLIENT_SECRET: '${INFISICAL_CLIENT_SECRET:-}',
          // Public URL by default (works on every host); per-host override allowed.
          INFISICAL_ADDRESS: '${INFISICAL_ADDRESS:-http://' + ref[role.APP] + ':' + std.toString(appPort) + '}',
        },
        healthcheck: {
          test: ['CMD-SHELL', '[ ! -f /tmp/agent.last_err ] || [ $$(( $$(date +%s) - $$(cat /tmp/agent.last_err) )) -ge 180 ]'],
          interval: '30s',
          timeout: '5s',
          retries: 2,
          start_period: '30s',
        },
      },
    },
    lib.network.attach(reg.networks.shared.infisicalDB)
  ),
  [lib.SecretOrBootstrap('infisical')],
)
