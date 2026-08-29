// `db` is this stack's own dedicated Postgres — it does NOT join the shared cluster.
// Vikunja reads discrete VIKUNJA_DATABASE_* values rather than one connection URL, so the
// shared-cluster pattern (store DATABASE_URL whole) buys nothing here; a dedicated instance
// keeps the whole trial to one stack that deletes cleanly.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'vikunja',

  app:: self.Service { role:: lib.collections.role.APP },
  db:: self.Service { role:: lib.collections.role.DB },

  dbData:: self.Volume { key:: 'db' },
};

local userID = "1000";
local userGroupID = userID + ":" + userID;

local appVersion = '2.5.0';
local dbVersion = '18';

local appPort = '3456';
local dbUser = refs.name;
local dbName = refs.name;

// Attachments live on a host bind mount, not a named volume. The image is `scratch` with
// `USER 1000` and never creates this directory, so an empty named volume has nothing to
// copy ownership from and lands root-owned — uploads then fail. The host path is chowned to
// 1000 by the stack's pre_deploy in sync.toml.
local filesDir = lib.collections.dirs.docker.bindMounts + '/apps/vikunja/files';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    volumes: refs.dbData.declare,

    services: {
      // Injects every secret under /vikunja into the services that depend on it, each under
      // its own Infisical name.
      [lib.collections.role.SECRETS]: lib.SecretsProvider('apps', '/vikunja'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'docker.io/vikunja/vikunja:' + appVersion,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady {
          [refs.db.key]: { condition: lib.collections.condition.healthy },
        },
        volumes: [filesDir + ':/app/vikunja/files'],
        // VIKUNJA_DATABASE_PASSWORD and VIKUNJA_SERVICE_SECRET arrive from
        // infisical-secrets. VIKUNJA_SERVICE_SECRET signs JWTs: leave it unset and Vikunja
        // generates a fresh one per start, invalidating every session on restart.
        environment: {
          VIKUNJA_DATABASE_TYPE: 'postgres',
          VIKUNJA_DATABASE_HOST: refs.db.key,
          VIKUNJA_DATABASE_USER: dbUser,
          VIKUNJA_DATABASE_DATABASE: dbName,

          VIKUNJA_SERVICE_PUBLICURL: 'https://%s.%s' % [refs.name, lib.collections.domain.ktbinternal],
          VIKUNJA_SERVICE_TIMEZONE: 'America/New_York',
          // Open so the first account can be made through the UI. Flip to 'false' once it
          // exists — there is no invite flow, and the instance is otherwise self-serve.
          VIKUNJA_SERVICE_ENABLEREGISTRATION: 'true',
        },
        // No healthcheck: the image is `scratch`, so it ships no shell, curl or wget, and
        // the vikunja binary has no health subcommand to exec instead.
        expose: [appPort],
        ports: ['%s:18026:%s' % [lib.collections.ip.loopback, appPort]],
        pre_start: [
          { command: ['sh', '-c', 'mkdir -p %s && chown %s %s' % [filesDir, userGroupID, filesDir]] }
        ],
      },

      [refs.db.key]: {
        container_name: refs.db.ext,
        image: 'docker.io/library/postgres:' + dbVersion,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        volumes: [refs.dbData.mount('/var/lib/postgresql')],
        // POSTGRES_PASSWORD arrives from infisical-secrets, holding the same value the app
        // reads as VIKUNJA_DATABASE_PASSWORD — the bundle carries it under both names.
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
        },
        healthcheck: {
          test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
          interval: '5s',
          timeout: '10s',
          retries: 10,
        },
        expose: ['5432'],
      },
    },
  },
}
