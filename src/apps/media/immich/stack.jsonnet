// Compiles to compose.yaml and stack.services.yaml — do not edit the YAML. Immich needs its own
// Postgres (vectorchord/pgvecto extensions) — does NOT join shared-postgres.
//
// Postgres + ML model cache live on local NVMe bind mounts (Postgres must NOT
// live on NFS); the photo/video library is a separate NFS export at the
// literal host path /mnt/immich-library.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'immich';
// Immich's own upstream service names — no reg.role equivalent, so plain locals.
local db = 'database';
local ml = 'machine-learning';
local app = role.SERVER;
local redis = 'redis';

local dbVersion = 'ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23';
local mlVersion = 'ghcr.io/immich-app/immich-machine-learning:v2.7.5';
local serverVersion = 'ghcr.io/immich-app/immich-server:v2.7.5';
local redisVersion = 'docker.io/valkey/valkey:9@sha256:8436e10bc65c94886a91d4415b6a6dfa9cb5a306fb3b996e5bb67cd2b4854193';

local port = 2283;
local tz = 'America/New_York';

local bindRoot = reg.dirs.docker.root + reg.dirs.docker.bindMounts + '/apps/immich';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [db]: lib.Service {
      image: dbVersion,
      mounts_:: [bindRoot + '/postgres:/var/lib/postgresql/data'],
      environment: {
        POSTGRES_DB: 'immich',
        POSTGRES_USER: 'immich',
        POSTGRES_INITDB_ARGS: '--data-checksums',
        // env_file interpolation of ${IMMICH_DB_PASSWORD} doesn't work — must be
        // set directly here.
        POSTGRES_PASSWORD: '${IMMICH_DB_PASSWORD:?err}',
      },
      shm_size: '128mb',
    },

    [ml]: lib.Service {
      image: mlVersion,
      mounts_:: [bindRoot + '/model-cache:/cache'],
      environment: {
        TZ: tz,
      },
    },

    [app]: lib.Service {
      image: serverVersion,
      // depends_on takes compose service KEYS, not container names — so the bare
      // roles, not ref[...].
      depends_on: [db, redis],
      mounts_:: ['/mnt/immich-library:/data'],
      // Intel Quick Sync HW transcoding (paiki's N150 iGPU). Equivalent to the
      // `quicksync` service in Immich's hwaccel.transcoding.yml. Enable in the UI:
      // Admin → Video Transcoding → Acceleration API → Quick Sync.
      devices: ['/dev/dri:/dev/dri'],
      environment: {
        TZ: tz,
        // Same env_file interpolation issue — use the actual container name,
        // which is what ref hands back.
        REDIS_HOSTNAME: ref[redis],
        DB_HOSTNAME: ref[db],
        DB_USERNAME: 'immich',
        DB_DATABASE_NAME: 'immich',
        // Same env_file interpolation bug as POSTGRES_PASSWORD above.
        DB_PASSWORD: '${IMMICH_DB_PASSWORD:?err}',
      },
      expose: [std.toString(port)],
      ports: ['%s:2283:%s' % [reg.ips.loopback, port]],
    },

    [redis]: lib.Service {
      image: redisVersion,
    },
  }),
  [lib.Secret('immich')],
)
