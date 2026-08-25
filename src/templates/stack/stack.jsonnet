// STANDARD STACK TEMPLATE — copy this directory to start a new stack, rename it in
// `refs`, then delete every service and field you do not need.
//
// It is a real, compiling stack, so a devlib change that breaks the library breaks this
// file and `mise run render` fails on the next commit.
//
// Under `compose` this is plain Compose. Everything is written literally except the names
// read in more than one place, which come from `refs`, and the secrets, which the
// infisical-secrets provider injects.
local lib = import 'lib.libsonnet';

// Every name this stack owns, in one table, so a name is written once even when it is read
// from four services. Nothing here is a compose document; it is a table of strings.
local refs = lib.Project {
  // The one string a stack has to choose. Containers become <name>_<role>, volumes
  // <name>_<key>, and it is the name the private bridge is given in stack.jsonnet.
  name:: 'example',  // ← rename me


  // Services, keyed by the role they play. Roles come from lib.collections.role rather than bare
  // strings, so `db` is never also `database` in another stack. A service whose name is
  // genuinely app-specific (guacd, gerbil) is a plain local instead.
  app:: self.Service { role:: lib.collections.role.APP },
  db:: self.Service { role:: lib.collections.role.DB },

  // Volumes this stack owns. The key is the compose-local handle; `name` is what it is
  // called on the host.
  appData:: self.Volume { key:: 'app' },
  dbData:: self.Volume { key:: 'db' },
};

local appVersion = 'latest';
local dbVersion = '18';
local appPort = '8080';
local dbUser = refs.name;
local dbName = refs.name;

{
  compose: {
    name: refs.name,
    // The private bridge every service joins implicitly. `default` is compose's reserved
    // key, not a name; the stack's name lands underneath it.
    networks: { default: { name: refs.name } },

    volumes: refs.appData.declare + refs.dbData.declare,

    services: {
      // Fetches this stack's bundle and injects every secret in it, under its own Infisical
      // name, into each service that depends on it. The first argument is a KEY into
      // registry.libsonnet's infisical.project; the second is the folder inside it.
      //
      // There is no compose-level interpolation left to rename a value or build one out of
      // parts, so a secret has to be stored under exactly the name the container reads — a
      // connection URL whole, not a user and a password to join together.
      [lib.collections.role.SECRETS]: lib.SecretsProvider('apps', '/example'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/example/example:' + appVersion,
        restart: lib.collections.restart.onFailure(5),

        // Published ports bind to loopback — apps are reached over the tailnet or through the
        // edge proxy, so a port that is not loopback-bound is a mistake, not a default.
        ports: ['%s:18000:%s' % [lib.collections.ip.loopback, appPort]],
        expose: [appPort],

        volumes: [refs.appData.mount('/data')],

        // A provider has no health of its own, so `started` is the only condition it can
        // satisfy — lib.secretsReady is that entry, ready to join a depends_on map.
        depends_on: lib.secretsReady {
          // Wait for the DB's healthcheck, not just its start.
          [refs.db.key]: { condition: lib.collections.condition.healthy },
        },

        // DB_PASSWORD arrives from infisical-secrets. A value written here that the bundle
        // also carries is overwritten by the bundle's, which is how a literal default stays
        // overridable per host.
        environment: {
          // Reach the DB by its compose key — docker resolves it on the private bridge.
          DB_HOST: refs.db.key,
          DB_NAME: dbName,
          DB_USER: dbUser,
          APP_URL: 'https://%s.%s' % [refs.name, lib.collections.domain.ktbinternal],
        },

        healthcheck: {
          test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:' + appPort],
          interval: '30s',
          timeout: '10s',
          retries: 5,
        },
      },

      // ── DB: dedicated Postgres ────────────────────────────────────────────────────
      // To use the SHARED cluster instead, delete this service and reach it by the level it
      // is on: same host, join shared__postgres_db and dial
      // lib.registry.endpoint.serviceGroup.postgres.container.addr; another host, dial
      // lib.registry.endpoint.serviceGroup.postgres.host.addr over the .internal zone.
      [refs.db.key]: {
        container_name: refs.db.ext,
        image: 'docker.io/library/postgres:' + dbVersion,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        expose: ['5432'],
        volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
        // POSTGRES_PASSWORD arrives from infisical-secrets. `app` reads the same password as
        // DB_PASSWORD, so the bundle has to carry it under both names — the provider injects
        // values, it does not rename them.
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
      },
    },
  },
}
