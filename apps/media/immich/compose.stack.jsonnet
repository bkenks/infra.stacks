// immich — self-hosted photo & video management (immich.<domains.ktbinternal>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Immich requires its own dedicated Postgres (vectorchord/pgvecto
// extensions) — it does NOT join shared-postgres. Only immich-server (the
// `server` role below) is Traefik-facing, joining shared-proxy.
//
// Storage: database + ML model cache are bind mounts under
// registry.dockerVolumes (local NVMe — Postgres must NOT live on NFS); the
// photo/video library is a separate NFS export mounted at the literal host
// path /mnt/immich-library (not under dockerVolumes).
local lib = import 'lib.libsonnet';

local stack = 'immich';
local n = lib.compose.names(stack);
local db = 'database';
local ml = 'machine-learning';
local app = 'server';
local redis = lib.registry.roles.redis;

local dbVersion = 'ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23';
local mlVersion = 'ghcr.io/immich-app/immich-machine-learning:v2.7.5';
local serverVersion = 'ghcr.io/immich-app/immich-server:v2.7.5';
local redisVersion = 'docker.io/valkey/valkey:9@sha256:8436e10bc65c94886a91d4415b6a6dfa9cb5a306fb3b996e5bb67cd2b4854193';

local port = 2283;
local tz = 'America/New_York';

{
  name: stack,

  services: {
    [db]: {
      image: dbVersion,
      container_name: n.container(db),
      volumes: [lib.registry.dockerVolumes + '/apps/immich/postgres:/var/lib/postgresql/data'],
      environment: {
        POSTGRES_DB: 'immich',
        POSTGRES_USER: 'immich',
        POSTGRES_INITDB_ARGS: '--data-checksums',
        // Secret — interpolated from /dev/shm/immich.env (parent include.env_file).
        // Was broken pre-jsonnet: ${IMMICH_DB_PASSWORD} inside env_file: doesn't
        // interpolate. Fixed here by putting it directly in `environment:`.
        POSTGRES_PASSWORD: '${IMMICH_DB_PASSWORD:?err}',
      },
      restart: 'unless-stopped',
      shm_size: '128mb',
      networks: {
        default: { aliases: [n.alias(db)] },
      },
    },

    [ml]: {
      image: mlVersion,
      container_name: n.container(ml),
      volumes: [lib.registry.dockerVolumes + '/apps/immich/model-cache:/cache'],
      environment: {
        TZ: tz,
      },
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.alias(ml)] },
      },
    },

    [app]: {
      image: serverVersion,
      container_name: n.container(app),
      depends_on: [db, redis],
      volumes: ['/mnt/immich-library:/data'],
      environment: {
        TZ: tz,
        // Was broken pre-jsonnet: ${COMPOSE_PROJECT_NAME}-redis inside env_file:
        // doesn't interpolate. Fixed here with the actual container name.
        REDIS_HOSTNAME: n.container(redis),
        DB_HOSTNAME: n.container(db),
        DB_USERNAME: 'immich',
        DB_DATABASE_NAME: 'immich',
        // Secret — interpolated from /dev/shm/immich.env (parent include.env_file).
        // Same non-interpolation bug as above, fixed the same way.
        DB_PASSWORD: '${IMMICH_DB_PASSWORD:?err}',
      },
      restart: 'unless-stopped',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.alias(app)] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias(app)] },
      },
      labels: lib.mixins.proxyAdd('immich', 'immich', port),
    },

    [redis]: {
      image: redisVersion,
      container_name: n.container(redis),
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.alias(redis)] },
      },
    },
  },

  networks:
    n.network
    + lib.compose.join('proxy'),
}
