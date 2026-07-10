// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML. Immich needs its own
// Postgres (vectorchord/pgvecto extensions) — does NOT join shared-postgres.
//
// Postgres + ML model cache live on local NVMe bind mounts (Postgres must NOT
// live on NFS); the photo/video library is a separate NFS export at the
// literal host path /mnt/immich-library.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'immich';
local s = c.stack(stack);
local n = s.names;
local db = 'database';
local ml = 'machine-learning';
local app = 'server';
local redis = reg.roles.redis;

local dbVersion = 'ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23';
local mlVersion = 'ghcr.io/immich-app/immich-machine-learning:v2.7.5';
local serverVersion = 'ghcr.io/immich-app/immich-server:v2.7.5';
local redisVersion = 'docker.io/valkey/valkey:9@sha256:8436e10bc65c94886a91d4415b6a6dfa9cb5a306fb3b996e5bb67cd2b4854193';

local port = 2283;
local tz = 'America/New_York';

local manifest = {
  name: stack,

  services: {
    [db]: {
      image: dbVersion,
      container_name: n.container(db),
      volumes: [reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/immich/postgres:/var/lib/postgresql/data'],
      environment: {
        POSTGRES_DB: 'immich',
        POSTGRES_USER: 'immich',
        POSTGRES_INITDB_ARGS: '--data-checksums',
        // env_file interpolation of ${IMMICH_DB_PASSWORD} doesn't work — must be
        // set directly here.
        POSTGRES_PASSWORD: '${IMMICH_DB_PASSWORD:?err}',
      },
      restart: 'unless-stopped',
      shm_size: '128mb',
      networks: {
        default: { aliases: [n.container(db)] },
      },
    },

    [ml]: {
      image: mlVersion,
      container_name: n.container(ml),
      volumes: [reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/immich/model-cache:/cache'],
      environment: {
        TZ: tz,
      },
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.container(ml)] },
      },
    },

    [app]: {
      image: serverVersion,
      container_name: n.container(app),
      depends_on: [db, redis],
      volumes: ['/mnt/immich-library:/data'],
      environment: {
        TZ: tz,
        // Same env_file interpolation issue — use the actual container name.
        REDIS_HOSTNAME: n.container(redis),
        DB_HOSTNAME: n.container(db),
        DB_USERNAME: 'immich',
        DB_DATABASE_NAME: 'immich',
        // Same env_file interpolation bug as POSTGRES_PASSWORD above.
        DB_PASSWORD: '${IMMICH_DB_PASSWORD:?err}',
      },
      restart: 'unless-stopped',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add('immich', 'immich', port),
    },

    [redis]: {
      image: redisVersion,
      container_name: n.container(redis),
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.container(redis)] },
      },
    },
  },

  networks:
    s.network.default
    + s.network.join(reg.sharedNetworks.proxy),
};

c.render(stack, manifest, [secrets.immich.path])
