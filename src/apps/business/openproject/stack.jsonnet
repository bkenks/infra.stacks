// openproject: one Rails image run four ways — web, worker, cron and a one-shot seeder.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'openproject',

  // One Rails image run four ways, plus a cache and a watchdog.
  web:: self.Service { role:: lib.collections.role.WEB },
  worker:: self.Service { role:: lib.collections.role.WORKER },
  seeder:: self.Service { role:: lib.collections.role.SEEDER },
  cron:: self.Service { role:: 'cron' },
  cache:: self.Service { role:: lib.collections.role.CACHE },
  autoheal:: self.Service { role:: 'autoheal' },
  hocuspocus:: self.Service { role:: 'hocuspocus' },

  // Mounted by all four Rails services; declared once.
  assets:: self.Volume { key:: 'assets' },
};

local appVersion = '17-slim';
local hocuspocusVersion = '17.5.1';
local autohealVersion = '1.2.0';
local memcachedVersion = '1.6-alpine';

local webPort = '8080';
local hocuspocusPort = '1234';

// The public subdomain 'openprj' differs from the stack name 'openproject'.
local sub = 'openprj';
local cloudDomain = sub + '.' + lib.collections.domain.ktbcloud;
local internalDomain = sub + '.' + lib.collections.domain.ktbinternal;

local sharedDB = lib.registry.network.shared.postgresDB;

local appEnv = {
  OPENPROJECT_HTTPS: 'true',
  OPENPROJECT_HSTS: 'true',
  OPENPROJECT_RAILS__RELATIVE__URL__ROOT: '',
  RAILS_MIN_THREADS: '4',
  RAILS_MAX_THREADS: '8',
  // The image bundles libjemalloc but ships with it off; glibc malloc fragments badly
  // under Puma's threads, so enabling jemalloc reclaims ~20-35% of RSS.
  USE_JEMALLOC: 'true',
  IMAP_ENABLED: 'false',
  OPENPROJECT_HOST__NAME: cloudDomain,
  // `web` lets hocuspocus' internal callback (http://web:8080) pass the host check.
  OPENPROJECT_ADDITIONAL__HOST__NAMES:
    '[%s, %s, %s]' % [cloudDomain, internalDomain, refs.web.key],
  OPENPROJECT_URL: 'https://' + cloudDomain,
  OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__URL: 'wss://%s/hocuspocus' % cloudDomain,
  OPENPROJECT_RAILS__CACHE__STORE: 'memcache',
  OPENPROJECT_CACHE__MEMCACHE__SERVER: refs.cache.key + ':11211',
  OPENPROJECT_EE__HIDE__BANNERS: 'true',
  OPENPROJECT_EE__MANAGER__VISIBLE: 'false',
  OPENPROJECT_WELCOME__ON__HOMESCREEN: 'false',
  OPENPROJECT_DISABLED__MODULES: '',
  // DATABASE_URL, SECRET_KEY_BASE and OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET
  // arrive from infisical-secrets. DATABASE_URL is stored whole — there is no compose-level
  // interpolation left to assemble it from a user and a password, and it must be spelled
  // 'postgres://' not 'postgresql://': Ruby's uri gem does not pre-register the latter as
  // hierarchical and rejects the user:pass@ part.
};

// The shared body of the four Rails services.
local railsApp = {
  image: 'openproject/openproject:' + appVersion,
  restart: lib.collections.restart.unlessStopped,
  volumes: [
    refs.assets.mount('/var/openproject/assets'),
    './token/enterprise_token.rb:/app/app/models/enterprise_token.rb',
  ],
  environment: appEnv,
  // Postgres is the shared cluster on this host, reached over shared__postgres_db. Every
  // Rails service needs it — the seeder runs the migrations.
  networks: ['default', sharedDB.name],
  depends_on: lib.secretsReady,
};

// Map form, not a bare list: the secrets provider is joined in below and compose takes one
// shape or the other, never both. `service_started` is what a plain list already meant.
local afterSeed = lib.secretsReady {
  [refs.cache.key]: { condition: lib.collections.condition.started },
  [refs.seeder.key]: { condition: lib.collections.condition.started },
};

{
  compose: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [sharedDB.name]: { name: sharedDB.name, external: true },
    },
    volumes: refs.assets.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('apps', '/openproject'),

      // Restarts any container labelled autoheal=true once its healthcheck fails.
      [refs.autoheal.key]: {
        container_name: refs.autoheal.ext,
        image: 'willfarrell/autoheal:' + autohealVersion,
        restart: lib.collections.restart.unlessStopped,
        environment: {
          AUTOHEAL_CONTAINER_LABEL: 'autoheal',
          AUTOHEAL_START_PERIOD: '600',
          AUTOHEAL_INTERVAL: '30',
        },
        volumes: [lib.collections.mounts.dockerSockRW],
      },

      [refs.cache.key]: {
        container_name: refs.cache.ext,
        image: 'memcached:' + memcachedVersion,
        restart: lib.collections.restart.unlessStopped,
      },

      [refs.cron.key]: railsApp {
        container_name: refs.cron.ext,
        depends_on: afterSeed,
        command: './docker/prod/cron',
      },

      [refs.hocuspocus.key]: {
        container_name: refs.hocuspocus.ext,
        image: 'openproject/hocuspocus:' + hocuspocusVersion,
        restart: lib.collections.restart.unlessStopped,
        networks: ['default', sharedDB.name],
        depends_on: lib.secretsReady,
        // Calls back into `web` over the private bridge (http, not the TLS hairpin); `web`
        // must be in OPENPROJECT_ADDITIONAL__HOST__NAMES. SECRET arrives from
        // infisical-secrets and holds the same value the Rails services read as
        // OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET.
        environment: {
          OPENPROJECT_URL: 'http://%s:%s' % [refs.web.key, webPort],
          OPENPROJECT_HTTPS: 'true',
        },
        expose: [hocuspocusPort],
        ports: ['%s:%s:%s' % [lib.collections.ip.loopback, hocuspocusPort, hocuspocusPort]],
      },

      // Runs migrations and seeds, then exits; the long-running services wait on it.
      [refs.seeder.key]: railsApp {
        container_name: refs.seeder.ext,
        command: './docker/prod/seeder',
        restart: 'on-failure',
      },

      [refs.web.key]: railsApp {
        container_name: refs.web.ext,
        depends_on: afterSeed,
        command: './docker/prod/web',
        // One Puma worker instead of the default 2 — a whole forked Rails process saved; low
        // concurrency here does not need two. Bump back up if web slows.
        environment: appEnv { WEB_CONCURRENCY: '1' },
        labels: { autoheal: 'true' },
        healthcheck: {
          test: ['CMD', 'curl', '-f', 'http://localhost:%s/health_checks/default' % webPort],
          interval: '10s',
          timeout: '3s',
          retries: 3,
          start_period: '60s',
        },
        expose: [webPort],
        ports: ['%s:18009:%s' % [lib.collections.ip.loopback, webPort]],
      },

      [refs.worker.key]: railsApp {
        container_name: refs.worker.ext,
        depends_on: afterSeed,
        command: './docker/prod/worker',
      },
    },
  },
}
