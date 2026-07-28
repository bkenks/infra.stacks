// STANDARD STACK TEMPLATE — copy this file to start a new stack, change `name`, then
// delete every service and field you do not need.
//
// It exercises every feature the library has, so a lib/ change that breaks the library
// breaks this file and `mise run render` fails on the next commit. That is the point of
// keeping it a real, compiling stack rather than prose.
//
// The render contract (see .mise/tasks/render.py): this file evaluates to
// { '<filename>': <content>, … } and lib.render() does exactly that — emitting
//   compose.yaml   the project + an `include` of the manifest (what Docker loads)
//   services.yaml  the actual services/networks/volumes manifest
// render.py prefixes each with this file's stem, so they land as stack.compose.yaml and
// stack.services.yaml.
// Never edit those YAMLs; they carry a GENERATED header and are rewritten on commit.

local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

// The stack name — the one string a stack has to choose. Everything else derives from it:
// containers become <name>_<role> and volumes <name>_<key>, and it becomes the real name
// of the default network. Bound once and passed to both Stack() and render(), so the two
// can never disagree.
local name = 'example';  // ← rename me

local appVersion = 'latest';
local dbVersion = '18';
local appPort = 8080;
local dbUser = name;
local dbName = name;

lib.render(
  name,

  lib.Stack(name, function(ref) {
    // Services are keyed by role, taken from reg.role rather than typed as bare strings —
    // that is what keeps `db` from being `database` in some other stack. A service whose
    // name is genuinely app-specific (guacd, gerbil) uses a plain local instead.
    //
    // `ref` is the stack's own service table: ref[role.DB] is the name the db service will
    // actually carry *if this stack declares one*, and an evaluation error if it does not.
    // Use it for every cross-service reference — a typo fails at the point of the mistake
    // rather than in a container that never starts.
    [role.APP]: lib.Service {
      image: 'ghcr.io/example/example:' + appVersion,

      // Anything Compose understands can be set here; it passes straight through. Published
      // ports bind to loopback — apps are reached over the tailnet or through the edge
      // proxy, so a port that is not loopback-bound is a mistake, not a default.
      ports: ['%s:18000:%s' % [reg.ips.loopback, appPort]],
      expose: [std.toString(appPort)],

      // volumes_ is { key: '/path/in/container' } for volumes this stack owns. The key is
      // the compose-local handle; the real volume is registered at the top level as
      // <name>_<key>, so it is declared once, here, where it is mounted.
      volumes_:: { app: '/data' },

      // Bind mounts and host paths have no name to derive, so they pass through verbatim.
      // mounts_:: ['./files/config.yaml:/app/config.yaml:ro'],

      depends_on: {
        // Wait for the DB's healthcheck, not just its start, before booting.
        [role.DB]: { condition: 'service_healthy' },
      },

      environment: {
        // Reach the DB by the name ref hands back — it is both the compose key's container
        // and its DNS name on the stack network.
        DB_HOST: ref[role.DB],
        DB_NAME: dbName,
        DB_USER: dbUser,
        // `${VAR:?err}` makes Compose refuse to start when VAR is unset rather than
        // interpolating an empty string. Use it for everything out of the env file.
        DB_PASSWORD: '${EXAMPLE_DB_PASSWORD:?err}',
        APP_URL: 'https://%s.%s' % [name, reg.domains.ktbinternal],
      },

      // Every default the Service base sets — container_name, restart, the network alias —
      // is a plain field, so overriding one is just writing it again.
      restart: 'on-failure:5',

      healthcheck: {
        test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:' + std.toString(appPort)],
        interval: '30s',
        timeout: '10s',
        retries: 5,
      },
    },

    // ── DB: dedicated Postgres ────────────────────────────────────────────────────
    // To use the SHARED cluster instead, delete this service and dial it over the
    // host-gateway: point DB_HOST/DB_PORT at reg.endpoint.postgres.host and add
    // `extra_hosts: ['host.docker.internal:host-gateway']` to the app service. There are no
    // shared Docker networks — that gateway is how every cross-stack call is made.
    [role.DB]: lib.Service {
      image: 'docker.io/library/postgres:' + dbVersion,
      volumes_:: { db: '/var/lib/postgresql/data' },
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        POSTGRES_PASSWORD: '${EXAMPLE_DB_PASSWORD:?err}',
      },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
        interval: '5s',
        timeout: '10s',
        retries: 10,
      },
      expose: ['5432'],
    },
  }),

  // The env files the parent include interpolates into the manifest. Register the stack in
  // registry.libsonnet's infisical catalogue and reference it by KEY — lib.Secret('example')
  // — so the agent (producer) and this stack (consumer) derive the same path. Until it is
  // registered the literal below is fine. Drop the argument entirely for a no-secrets stack.
  [reg.secretPath + '/' + name + '.env'],
)
