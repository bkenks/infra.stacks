// authentik — self-hosted SSO / identity provider (auth.ktbcloud.com).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Four services on this stack's PRIVATE net (db, redis, server, worker);
// the server ALSO joins shared-edge (owned here) so the pangolin edge stack's
// Traefik can reach authentik_server:9000 for OIDC/forward-auth once wired.
// It does NOT join shared-proxy — nothing here is fronted by a per-host Traefik.
//
// server + worker share one image and one env base (opApp-style merge, mirroring
// apps/business/openproject): per-service keys below override command / ports /
// user / docker.sock / networks. env var names + volume layout verified against
// https://docs.goauthentik.io/install-config/install/docker-compose/ (compose.yml).
//
// Secrets are interpolated from /dev/shm/authentik.env (declared as the parent
// compose.yaml include.env_file) — see registry agentServices.authentik.
local lib = import 'lib.libsonnet';
local r = lib.registry;
local c = lib.compose;

local stack = 'authentik';
local n = c.names(stack);

local version = '2026.5.3';        // ghcr.io/goauthentik/server + proxy
local postgresVersion = '16-alpine';
local redisVersion = '7-alpine';

// Container names double as the in-stack DNS the app dials (AUTHENTIK_*__HOST).
local dbName = n.container('db');        // authentik_db
local redisName = n.container('redis');  // authentik_redis
local serverName = n.container('server');
local workerName = n.container('worker');

local mediaVol = n.volume('media');
local dbVol = n.volume('database');

// Shared base merged (via `+`) into server + worker.
local akVolumes = [
  mediaVol + ':/data',
  './files/blueprints:/blueprints/ktb:ro',
];
local akApp = {
  image: 'ghcr.io/goauthentik/server:' + version,
  restart: 'unless-stopped',
  shm_size: '512mb',  // authentik requires this for the embedded proxy/temp files
  volumes: akVolumes,
  depends_on: {
    [dbName]: { condition: 'service_healthy' },
    [redisName]: { condition: 'service_healthy' },
  },
};

// Literal (non-secret) config shared by server + worker.
local akEnv = {
  AUTHENTIK_POSTGRESQL__HOST: dbName,
  AUTHENTIK_POSTGRESQL__NAME: 'authentik',
  AUTHENTIK_POSTGRESQL__USER: 'authentik',
  AUTHENTIK_POSTGRESQL__SSLMODE: 'disable',
  AUTHENTIK_REDIS__HOST: redisName,
  AUTHENTIK_DISABLE_UPDATE_CHECK: 'true',
  AUTHENTIK_ERROR_REPORTING__ENABLED: 'false',
  AUTHENTIK_COOKIE_DOMAIN: 'ktbcloud.com',
};

// Secrets — interpolated from /dev/shm/authentik.env (parent include.env_file).
local akSecrets = {
  AUTHENTIK_SECRET_KEY: '${AUTHENTIK_SECRET_KEY:?err}',
  AUTHENTIK_POSTGRESQL__PASSWORD: '${AUTHENTIK_POSTGRESQL__PASSWORD:?err}',
  AUTHENTIK_BOOTSTRAP_PASSWORD: '${AUTHENTIK_BOOTSTRAP_PASSWORD:?err}',
  AUTHENTIK_BOOTSTRAP_TOKEN: '${AUTHENTIK_BOOTSTRAP_TOKEN:?err}',
  AUTHENTIK_BOOTSTRAP_EMAIL: '${AUTHENTIK_BOOTSTRAP_EMAIL:?err}',
};

local akHealth = {
  test: ['CMD', 'ak', 'healthcheck'],
  interval: '30s',
  timeout: '30s',
  retries: 5,
  start_period: '60s',
};

{
  name: stack,

  services: {
    [dbName]: {
      image: 'postgres:' + postgresVersion,
      container_name: dbName,
      restart: 'unless-stopped',
      environment: {
        POSTGRES_USER: 'authentik',
        POSTGRES_DB: 'authentik',
        // Uses its own var (mapped from PG_PASS in the registry authentik map,
        // same source as the app's AUTHENTIK_POSTGRESQL__PASSWORD).
        POSTGRES_PASSWORD: '${POSTGRES_PASSWORD:?err}',
      },
      volumes: [dbVol + ':/var/lib/postgresql/data'],
      healthcheck: {
        test: ['CMD-SHELL', 'pg_isready -U authentik -d authentik'],
        interval: '30s',
        timeout: '5s',
        retries: 5,
        start_period: '20s',
      },
      networks: { default: { aliases: [dbName] } },
    },

    [redisName]: {
      image: 'docker.io/library/redis:' + redisVersion,
      container_name: redisName,
      restart: 'unless-stopped',
      command: ['--save', '60', '1'],
      healthcheck: {
        test: ['CMD-SHELL', 'redis-cli ping | grep PONG'],
        interval: '30s',
        timeout: '3s',
        retries: 5,
        start_period: '20s',
      },
      networks: { default: { aliases: [redisName] } },
    },

    // HTTP/OIDC front. Joins shared-edge so the pangolin Traefik can reach it at
    // authentik_server:9000 once forward-auth / OIDC routes are wired (Phase 2).
    [serverName]: akApp + {
      container_name: serverName,
      command: ['server'],
      environment: akEnv + akSecrets,
      ports: ['9000:9000'],
      healthcheck: akHealth,
      networks: {
        default: { aliases: [serverName] },
        [r.sharedNetworks.edge.name]: { aliases: [serverName] },
      },
    },

    // Background worker: runs migrations, applies blueprints, manages outposts —
    // needs the docker socket + root to spin up embedded/managed outposts.
    [workerName]: akApp + {
      container_name: workerName,
      command: ['worker'],
      user: 'root',
      volumes: akVolumes + ['/var/run/docker.sock:/var/run/docker.sock'],
      environment: akEnv + akSecrets,
      healthcheck: akHealth,
      networks: { default: { aliases: [workerName] } },
    },
  },

  volumes: {
    [mediaVol]: { name: mediaVol },
    [dbVol]: { name: dbVol },
  },

  networks:
    n.network            // private default net (db/redis/server/worker)
    + lib.compose.own('edge'),  // create shared-edge (this stack owns it)
}
