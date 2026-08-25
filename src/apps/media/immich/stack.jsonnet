// Immich needs its own Postgres (vectorchord/pgvecto extensions) — it does NOT join the
// shared cluster. Postgres and the ML model cache live on local NVMe bind mounts (Postgres
// must NOT live on NFS); the photo/video library is a separate NFS export at the literal
// host path /mnt/immich-library.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'immich',

  // Immich's own upstream component names — no lib.collections.role equivalent.
  database:: self.Service { role:: 'database' },
  machineLearning:: self.Service { role:: 'machine-learning' },
  redis:: self.Service { role:: 'redis' },
  server:: self.Service { role:: lib.collections.role.SERVER },
};

local dbImage = 'ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23';
local mlImage = 'ghcr.io/immich-app/immich-machine-learning:v2.7.5';
local serverImage = 'ghcr.io/immich-app/immich-server:v2.7.5';
local redisImage = 'docker.io/valkey/valkey:9@sha256:8436e10bc65c94886a91d4415b6a6dfa9cb5a306fb3b996e5bb67cd2b4854193';

local port = '2283';
local tz = 'America/New_York';
local bindRoot = lib.collections.dirs.docker.bindMounts + '/apps/immich';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('apps', '/immich'),

      [refs.database.key]: {
        container_name: refs.database.ext,
        image: dbImage,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady,
        volumes: [bindRoot + '/postgres:/var/lib/postgresql/data'],
        // POSTGRES_PASSWORD arrives from infisical-secrets; `server` reads the same value
        // as DB_PASSWORD, so the bundle carries it under both names.
        environment: {
          POSTGRES_DB: refs.name,
          POSTGRES_USER: refs.name,
          POSTGRES_INITDB_ARGS: '--data-checksums',
        },
        shm_size: '128mb',
      },

      [refs.machineLearning.key]: {
        container_name: refs.machineLearning.ext,
        image: mlImage,
        restart: lib.collections.restart.unlessStopped,
        volumes: [bindRoot + '/model-cache:/cache'],
        environment: { TZ: tz },
      },

      [refs.redis.key]: {
        container_name: refs.redis.ext,
        image: redisImage,
        restart: lib.collections.restart.unlessStopped,
      },

      [refs.server.key]: {
        container_name: refs.server.ext,
        image: serverImage,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady {
          [refs.database.key]: { condition: lib.collections.condition.started },
          [refs.redis.key]: { condition: lib.collections.condition.started },
        },
        volumes: ['/mnt/immich-library:/data'],
        // Intel Quick Sync HW transcoding (paiki's N150 iGPU) — the equivalent of the
        // `quicksync` service in Immich's hwaccel.transcoding.yml. Enable it in the UI:
        // Admin -> Video Transcoding -> Acceleration API -> Quick Sync.
        devices: ['/dev/dri:/dev/dri'],
        // DB_PASSWORD arrives from infisical-secrets.
        environment: {
          TZ: tz,
          REDIS_HOSTNAME: refs.redis.ext,
          DB_HOSTNAME: refs.database.ext,
          DB_USERNAME: refs.name,
          DB_DATABASE_NAME: refs.name,
        },
        expose: [port],
        ports: ['%s:2283:%s' % [lib.collections.ip.loopback, port]],
      },
    },
  },
}
