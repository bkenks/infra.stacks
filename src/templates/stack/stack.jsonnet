// STANDARD STACK TEMPLATE — copy this directory to start a new stack, rename it in
// `refs`, then delete every service and field you do not need.
//
// It is a real, compiling stack, so a devlib change that breaks the library breaks this
// file and `mise run render` fails on the next commit.
//
// Under `services` this is plain Compose. Everything is written literally except the names
// the manifest and the compose document have to agree on, which come from `refs`.
local lib = import 'lib.libsonnet';

// Every name this stack owns, in one table, so a name is written once even when it is read
// from four services. Nothing here is a compose document; it is a table of strings.
local refs = lib.Project {
  // The one string a stack has to choose. Containers become <name>_<role>, volumes
  // <name>_<key>, and it is the name the private bridge is given in stack.jsonnet.
  name:: 'example',  // ← rename me

  // The env files compose interpolates into services.yaml. Register the bundle in
  // devlib/registry.libsonnet and pass the KEY, so the agent and this stack derive the same
  // path: `lib.Secret('example')`. Until it is registered, spell it out. A stack with no
  // secrets drops this field entirely.
  envFiles:: [lib.collections.dirs.secrets + '/example.env'],

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
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    // The private bridge every service joins implicitly. `default` is compose's reserved
    // key, not a name; the stack's name lands underneath it.
    networks: { default: { name: refs.name } },

    volumes: refs.appData.declare + refs.dbData.declare,

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/example/example:' + appVersion,
        restart: lib.collections.restart.onFailure(5),

        // Published ports bind to loopback — apps are reached over the tailnet or through the
        // edge proxy, so a port that is not loopback-bound is a mistake, not a default.
        ports: ['%s:18000:%s' % [lib.collections.ip.loopback, appPort]],
        expose: [appPort],

        volumes: [refs.appData.mount('/data')],

        depends_on: {
          // Wait for the DB's healthcheck, not just its start.
          [refs.db.key]: { condition: lib.collections.condition.healthy },
        },

        environment: {
          // Reach the DB by its compose key — docker resolves it on the private bridge.
          DB_HOST: refs.db.key,
          DB_NAME: dbName,
          DB_USER: dbUser,
          // `${VAR:?err}` makes compose refuse to start when VAR is unset rather than
          // interpolating an empty string. Use it for everything out of the env file.
          DB_PASSWORD: '${EXAMPLE_DB_PASSWORD:?err}',
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
        expose: ['5432'],
        volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
          POSTGRES_PASSWORD: '${EXAMPLE_DB_PASSWORD:?err}',
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
