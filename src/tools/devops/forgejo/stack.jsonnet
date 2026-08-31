// forgejo: source-of-truth git forge (push-mirrors to GitHub). SSH via a raw-TCP Traefik
// router on :22. `db` is a dedicated Postgres, NOT the shared cluster.
local lib = import 'lib.libsonnet';
local col = lib.collections;

local refs = lib.Project {
  name:: 'forgejo',

  // Forgejo's own docs call it `server`, and the old stack did too.
  server:: self.Service { role:: lib.collections.role.SERVER },
  db:: self.Service { role:: lib.collections.role.DB },

  serverData:: self.Volume { key:: 'server' },
  dbData:: self.Volume { key:: 'db' },
};

// Pinned to a fork image (codeberg upstream had issues) — do NOT revert to upstream.
local serverImage = 'forgejoclone/forgejo:15';
local dbVersion = '14';
local port = '3000';
local dbUser = refs.name;
local dbName = refs.name;

{
  compose: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
    },
    volumes: refs.serverData.declare + refs.dbData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/forgejo'),

      [refs.server.key]: {
        container_name: refs.server.ext,
        image: serverImage,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        volumes: [
          refs.serverData.mount('/data'),
          '/etc/localtime:/etc/localtime:ro',
        ],
        // FORGEJO__database__PASSWD arrives from infisical-secrets; `db` reads the same
        // password as POSTGRES_PASSWORD, so the bundle carries it under both names.
        environment: {
          FORGEJO____APP_NAME: 'KTB Software',
          FORGEJO____APP_SLOGAN: 'End-To-End Software',
          FORGEJO____DOMAIN: col.domain.ktbcloud,
          FORGEJO____SSH_DOMAIN: col.domain.ktbcloud,
          FORGEJO__database__DB_TYPE: 'postgres',
          FORGEJO__database__HOST: refs.db.key + ':5432',
          FORGEJO__database__NAME: dbName,
          FORGEJO__database__USER: dbUser,
          USER_UID: '1000',
          USER_GID: '1000',
        },
        expose: [port, '22'],
        // 127.0.0.1:22 -> container SSH, dialled by bare-metal Newt (Pangolin edge on the VPS).
        ports: [
          '%s:18003:%s' % [lib.collections.ip.loopback, port],
          '%s:22:22' % lib.collections.ip.loopback,
        ],
      },

      [refs.db.key]: {
        container_name: refs.db.ext,
        image: 'docker.io/library/postgres:' + dbVersion,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        networks: ['default'],
        volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
        // POSTGRES_PASSWORD arrives from infisical-secrets.
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
        },
        expose: ['5432'],
        ports: ['%s:18041:5432' % lib.collections.ip.loopback],
      },
    },
  },
}
