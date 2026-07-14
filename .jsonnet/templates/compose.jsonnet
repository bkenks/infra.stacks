// ─────────────────────────────────────────────────────────────────────────────
// STANDARD STACK TEMPLATE — copy this file to start a new stack.
//
//   1. Copy this file to <area>/<stack>/compose.jsonnet
//      (area = apps/… | platform/… | tools/…).
//   2. Rename `stack` below — it is the compose project name AND the prefix for
//      every container/volume name (n.container / n.volume).
//   3. Delete the services/blocks you don't need; uncomment the variations you do.
//   4. Register secrets in registry.libsonnet's infisical catalogue, then point
//      `envFile` at secrets.<stack>.path (see the ENV FILE note below).
//
// The render contract (see .jsonnet/render.py): this file must evaluate to
// { '<filename>': <content>, … } and c.render() does exactly that — emitting
//   compose.yaml        the project + an `include` of the manifest (what Docker loads)
//   compose.stack.yaml  the actual services/networks/volumes manifest
// Never edit those YAMLs; they carry a GENERATED header and are rewritten on commit.
//
// Reference by KEY, never raw string: reg.sharedNetworks.proxy (not 'shared-proxy'),
// reg.roles.db (not 'db'). A typo'd key fails at compile time; a typo'd string fails
// silently at runtime. Helpers live in .jsonnet/lib/compose.libsonnet; cross-stack
// names live in .jsonnet/lib/registry.libsonnet. See README.md here for the full
// cheat-sheet of which helper covers which case.
// ─────────────────────────────────────────────────────────────────────────────
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'example';        // ← rename me
local s = c.stack(stack);       // name/network/proxy helpers scoped to this stack
local n = s.names;              // n.container(role) / n.volume(role) → 'example_<role>'

local app = reg.roles.app;      // 'app'  — reg.roles.{app,db,redis} are the shared role names
local db = reg.roles.db;        // 'db'

// Pin versions here, one local per image — keeps the manifest readable and the
// upgrade a one-line diff.
local appVersion = 'latest';
local dbVersion = '18';

local appPort = 8080;           // container port the app listens on
local dbUser = stack;
local dbName = stack;

// ENV FILE — the secrets file the parent compose.yaml interpolates into this manifest.
// Preferred: register this stack in registry.libsonnet (infisical.catalogue) and use
//   local envFile = secrets.<stack>.path;
// so the agent (producer) and this stack (consumer) can't disagree on the filename.
// Until registered, this literal is fine. A no-secrets stack omits envFile entirely
// and calls `c.render(stack, manifest)` with no third arg (see mazanoke).
local envFile = reg.secretDir + '/' + stack + '.env';

local manifest = {
  name: stack,

  services: {
    // ── App: the user-facing service, behind Traefik ───────────────────────────
    [app]: {
      image: 'ghcr.io/example/example:' + appVersion,
      container_name: n.container(app),
      depends_on: {
        // Wait for the DB's healthcheck, not just its start, before booting.
        [db]: { condition: 'service_healthy' },
      },
      volumes: [n.volume(app) + ':/data'],
      environment: {
        // Reach the DB by its container name on the shared default network.
        DB_HOST: n.container(db),
        DB_NAME: dbName,
        DB_USER: dbUser,
        // Secret — `${VAR:?err}` aborts the deploy if the env file hasn't supplied VAR.
        // Some images won't interpolate env_file values into every field; when that
        // bites, set the literal `${VAR:?err}` here in `environment:` (see immich).
        DB_PASSWORD: '${EXAMPLE_DB_PASSWORD:?err}',
        APP_URL: 'https://' + stack + '.' + reg.domains.ktbinternal,
      },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:' + std.toString(appPort)],
        interval: '30s',
        timeout: '10s',
        retries: 5,
      },
      // On the private default net (talks to db) AND the shared proxy net (Traefik).
      networks: {
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      // Traefik router: <router>, <subdomain>, <port>. Default zone is ktbinternal.
      labels: s.proxy.add(stack, stack, appPort),
      expose: [std.toString(appPort)],
    } + c.publish(18000, appPort),  // ← pick a free host port; binds 127.0.0.1 only

    // ── DB: dedicated Postgres (NOT shared-postgres) ───────────────────────────
    // To use the SHARED cluster instead, delete this whole service and see the
    // "shared-postgres" variation in README.md.
    [db]: {
      image: 'docker.io/library/postgres:' + dbVersion,
      container_name: n.container(db),
      volumes: [n.volume(db) + ':/var/lib/postgresql/data'],
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
      networks: { default: { aliases: [n.container(db)] } },
      expose: ['5432'],
    },

    // ── Redis (optional) — uncomment for apps that need a broker/cache ──────────
    // [reg.roles.redis]: {
    //   image: 'docker.io/library/redis:8',
    //   container_name: n.container(reg.roles.redis),
    //   command: ['--maxmemory-policy', 'noeviction'],
    //   restart: 'on-failure:5',
    //   healthcheck: {
    //     test: ['CMD', 'redis-cli', 'ping'],
    //     interval: '5s', timeout: '5s', retries: 10,
    //   },
    //   networks: { default: { aliases: [n.container(reg.roles.redis)] } },
    //   expose: ['6379'],
    // },
  },

  volumes: {
    [n.volume(app)]: { name: n.volume(app) },
    [n.volume(db)]: { name: n.volume(db) },
  },

  // default (private) net + the shared proxy net (external, Traefik owns it).
  // Join a shared net with s.network.join(reg.sharedNetworks.<x>); own one you
  // create with s.network.own(...). See README.md for the full network map.
  networks:
    s.network.default
    + s.network.join(reg.sharedNetworks.proxy),
};

// Third arg is the list of env files the parent include interpolates. Drop it for a
// no-secrets stack; pass several (e.g. [secrets.<stack>.path, secrets.postgres.path])
// when the stack also needs the shared-postgres credentials.
c.render(stack, manifest, [envFile])
