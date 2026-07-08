// openproject — self-hosted project management (openprj.<domains.ktbinternal>). One image
// (cron/seeder/web/worker) plus sidecars: cache (memcached), hocuspocus
// (collaborative editing), autoheal (restarts unhealthy containers).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) so web/hocuspocus are reachable and
// shared-postgres (postgres owns) so cron/seeder/web/worker reach their DB.
local lib = import 'lib.libsonnet';

local stack = 'openproject';
local n = lib.compose.names(stack);
local pgHost = lib.registry.endpoints.postgres.private.host;  // 'postgres_db'
local pgPort = lib.registry.endpoints.postgres.private.port;  // 5432

// Public host: subdomain is 'openprj', NOT the stack name 'openproject'.
local sub = 'openprj';
local domain = sub + '.' + lib.registry.domains.ktbinternal;

local appVersion = '17-slim';       // openproject/openproject — cron, seeder, web, worker
local hocuspocusVersion = '17.5.1'; // openproject/hocuspocus
local autohealVersion = '1.2.0';    // willfarrell/autoheal
local memcachedVersion = '1.6-alpine';

local webPort = 8080;
local hocuspocusPort = 1234;

// Shared base merged (via `+`) into cron/seeder/web/worker; per-service keys
// below override/extend these. enterprise_token.rb bind mount lands on all four.
local opApp = {
  image: 'openproject/openproject:' + appVersion,
  volumes: [
    n.volume('assets') + ':/var/openproject/assets',
    './token/enterprise_token.rb:/app/app/models/enterprise_token.rb',
  ],
  restart: 'unless-stopped',
};

// Literal (non-secret) config, common to cron/seeder/web/worker.
local opAppEnv = {
  OPENPROJECT_HTTPS: 'true',
  OPENPROJECT_HSTS: 'true',
  OPENPROJECT_RAILS__RELATIVE__URL__ROOT: '',
  RAILS_MIN_THREADS: '4',
  RAILS_MAX_THREADS: '16',
  IMAP_ENABLED: 'false',
  OPENPROJECT_HOST__NAME: domain,
  // `web` allows hocuspocus' internal callback (http://web:8080) to pass the host check.
  OPENPROJECT_ADDITIONAL__HOST__NAMES: domain + ',web',
  OPENPROJECT_URL: 'https://' + domain,
  // "wss" for secure websocket since the collab server is proxied behind TLS.
  OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__URL: 'wss://' + domain + '/hocuspocus',
  OPENPROJECT_RAILS__CACHE__STORE: 'memcache',
  OPENPROJECT_CACHE__MEMCACHE__SERVER: 'cache:11211',
  OPENPROJECT_EE__HIDE__BANNERS: 'true',
  OPENPROJECT_EE__MANAGER__VISIBLE: 'false',
  OPENPROJECT_WELCOME__ON__HOMESCREEN: 'false',
  OPENPROJECT_DISABLED__MODULES: '',
};

// Secrets — interpolated from /dev/shm/openproject.env + /dev/shm/postgres.env
// (parent include.env_file). Common to cron/seeder/web/worker.
local opAppSecrets = {
  // BUG FIX vs the old stack: host was hardcoded 'postgres', which only resolved
  // by luck/alias collision — use the shared-postgres registry endpoint host.
  // 'postgres://' (not 'postgresql://') trips Ruby's uri gem: it isn't a
  // pre-registered hierarchical scheme, so URI.parse rejects the user:pass@
  // registry part with "the scheme postgres does not accept registry part".
  DATABASE_URL: 'postgres://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + std.toString(pgPort) + '/openproject?pool=20&encoding=unicode&reconnect=true',
  SECRET_KEY_BASE: '${OPEN_PRJ_SECRET_KEY:?err}',
  OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET: '${COLLAB_SERVER_SECRET:?err}',
};

local webLabels = lib.mixins.proxyAdd(stack, sub, webPort) + { autoheal: 'true' };

// proxyAdd only builds a plain Host() rule; hocuspocus needs the same host PLUS
// a PathPrefix match at higher priority so it wins over the `web` catch-all.
local hocuspocusLabels = lib.mixins.proxyAdd(stack + '-hocuspocus', sub, hocuspocusPort) + {
  ['traefik.http.routers.' + stack + '-hocuspocus.rule']: 'Host(`' + domain + '`) && PathPrefix(`/hocuspocus`)',
  ['traefik.http.routers.' + stack + '-hocuspocus.priority']: '100',
};

{
  name: stack,

  services: {
    // No explicit `networks:` (implicit default only) — matches old behavior.
    autoheal: {
      image: 'willfarrell/autoheal:' + autohealVersion,
      container_name: n.container('autoheal'),
      environment: {
        AUTOHEAL_CONTAINER_LABEL: 'autoheal',
        AUTOHEAL_START_PERIOD: '600',
        AUTOHEAL_INTERVAL: '30',
      },
      volumes: ['/var/run/docker.sock:/var/run/docker.sock'],
      restart: 'unless-stopped',
    },

    cache: {
      image: 'memcached:' + memcachedVersion,
      container_name: n.container('cache'),
      restart: 'unless-stopped',
    },

    cron: opApp + {
      container_name: n.container('cron'),
      depends_on: ['cache', 'seeder'],
      command: './docker/prod/cron',
      environment: opAppEnv + opAppSecrets,
      networks: {
        default: { aliases: [n.alias('cron')] },
        [lib.registry.sharedNetworks.postgres.name]: { aliases: [n.alias('cron')] },
      },
    },
    hocuspocus: {
      image: 'openproject/hocuspocus:' + hocuspocusVersion,
      container_name: n.container('hocuspocus'),
      restart: 'unless-stopped',
      // Calls BACK into OpenProject to authenticate editing sessions. Reach `web`
      // internally over the `default` net (http, not the TLS hairpin); `web` must
      // be in OPENPROJECT_ADDITIONAL__HOST__NAMES so the host check passes.
      environment: {
        OPENPROJECT_URL: 'http://web:8080',
        OPENPROJECT_HTTPS: 'true',
        SECRET: '${COLLAB_SERVER_SECRET:?err}',
      },
      expose: [std.toString(hocuspocusPort)],
      networks: {
        default: { aliases: [n.alias('hocuspocus')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('hocuspocus')] },
      },
      labels: hocuspocusLabels,
    },

    seeder: opApp + {
      container_name: n.container('seeder'),
      command: './docker/prod/seeder',
      restart: 'on-failure',
      environment: opAppEnv + opAppSecrets,
      networks: {
        default: { aliases: [n.alias('seeder')] },
        [lib.registry.sharedNetworks.postgres.name]: { aliases: [n.alias('seeder')] },
      },
    },

    web: opApp + {
      container_name: n.container('web'),
      depends_on: ['cache', 'seeder'],
      command: './docker/prod/web',
      healthcheck: {
        test: ['CMD', 'curl', '-f', 'http://localhost:' + std.toString(webPort) + '/health_checks/default'],
        interval: '10s',
        timeout: '3s',
        retries: 3,
        start_period: '60s',
      },
      environment: opAppEnv + opAppSecrets,
      labels: webLabels,
      expose: [std.toString(webPort)],
      networks: {
        default: { aliases: [n.alias('web')] },
        [lib.registry.sharedNetworks.postgres.name]: { aliases: [n.alias('web')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('web')] },
      },
    },

    worker: opApp + {
      container_name: n.container('worker'),
      depends_on: ['cache', 'seeder'],
      command: './docker/prod/worker',
      environment: opAppEnv + opAppSecrets,
      networks: {
        default: { aliases: [n.alias('worker')] },
        [lib.registry.sharedNetworks.postgres.name]: { aliases: [n.alias('worker')] },
      },
    },
  },

  volumes: { [n.volume('assets')]: { name: n.volume('assets') } },

  networks:
    n.network
    + lib.compose.join('proxy')
    + lib.compose.join('postgres'),
}
