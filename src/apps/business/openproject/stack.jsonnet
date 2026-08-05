// openproject: one Rails image run four ways — web, worker, cron and a one-shot seeder.
// Compiles to compose.yaml and stack.services.yaml — do not edit the YAML.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'openproject';
local pgHost = reg.endpoint.postgres.container.host;  // 'host.docker.internal'
local pgPort = reg.endpoint.postgres.container.port;  // 6109

// Public subdomain 'openprj' differs from the stack name 'openproject'.
local sub = 'openprj';
local cloudDomain = sub + '.' + reg.domains.ktbcloud;
local internalDomain = sub + '.' + reg.domains.ktbinternal;

local appVersion = '17-slim';
local hocuspocusVersion = '17.5.1';
local autohealVersion = '1.2.0';
local memcachedVersion = '1.6-alpine';

local webPort = 8080;
local hocuspocusPort = 1234;

// App-specific service names with no entry in reg.role.
local AUTOHEAL = 'autoheal';
local CRON = 'cron';
local HOCUSPOCUS = 'hocuspocus';

local opAppEnv = {
  OPENPROJECT_HTTPS: 'true',
  OPENPROJECT_HSTS: 'true',
  OPENPROJECT_RAILS__RELATIVE__URL__ROOT: '',
  RAILS_MIN_THREADS: '4',
  RAILS_MAX_THREADS: '8',
  // The image bundles libjemalloc but ships with it off; glibc malloc fragments
  // badly under Puma's threads, so enabling jemalloc reclaims ~20-35% of RSS.
  USE_JEMALLOC: 'true',
  IMAP_ENABLED: 'false',
  OPENPROJECT_HOST__NAME: cloudDomain,
  // `web` allows hocuspocus' internal callback (http://web:8080) to pass the host check.
  OPENPROJECT_ADDITIONAL__HOST__NAMES: '[' + cloudDomain + ', ' + internalDomain + ', ' + role.WEB + ']',
  OPENPROJECT_URL: 'https://' + cloudDomain,
  OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__URL: 'wss://' + cloudDomain + '/hocuspocus',
  OPENPROJECT_RAILS__CACHE__STORE: 'memcache',
  OPENPROJECT_CACHE__MEMCACHE__SERVER: role.CACHE + ':11211',
  OPENPROJECT_EE__HIDE__BANNERS: 'true',
  OPENPROJECT_EE__MANAGER__VISIBLE: 'false',
  OPENPROJECT_WELCOME__ON__HOMESCREEN: 'false',
  OPENPROJECT_DISABLED__MODULES: '',
};

local opAppSecrets = {
  // Must be 'postgres://' not 'postgresql://': Ruby's uri gem doesn't
  // pre-register the latter as hierarchical and rejects the user:pass@ part.
  DATABASE_URL: 'postgres://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + std.toString(pgPort) + '/openproject?pool=20&encoding=unicode&reconnect=true',
  SECRET_KEY_BASE: '${OPEN_PRJ_SECRET_KEY:?err}',
  OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__SECRET: '${COLLAB_SERVER_SECRET:?err}',
};

// The shared body of the four Rails services. Each declares `assets`, and Stack()
// collapses the four declarations into the single top-level openproject_assets volume.
local opApp = lib.Service {
  image: 'openproject/openproject:' + appVersion,
  volumes_:: { assets: '/var/openproject/assets' },
  mounts_:: ['./token/enterprise_token.rb:/app/app/models/enterprise_token.rb'],
  environment: opAppEnv + opAppSecrets,
  // Postgres is the shared cluster, dialled through the docker host-gateway.
  extra_hosts: ['host.docker.internal:host-gateway'],
};

local webLabels = { autoheal: 'true' };

lib.render(
  name,
  lib.Stack(name, function(ref) {
    // Restarts any container labelled autoheal=true once its healthcheck fails.
    [AUTOHEAL]: lib.Service {
      image: 'willfarrell/autoheal:' + autohealVersion,
      environment: {
        AUTOHEAL_CONTAINER_LABEL: 'autoheal',
        AUTOHEAL_START_PERIOD: '600',
        AUTOHEAL_INTERVAL: '30',
      },
      // Deliberately not :ro — restarting containers is a write on the socket.
      mounts_:: ['/var/run/docker.sock:/var/run/docker.sock'],
    },

    [role.CACHE]: lib.Service {
      image: 'memcached:' + memcachedVersion,
    },

    [CRON]: opApp {
      depends_on: [role.CACHE, role.SEEDER],
      command: './docker/prod/cron',
    },

    [HOCUSPOCUS]: lib.Service {
      image: 'openproject/hocuspocus:' + hocuspocusVersion,
      // Calls back into `web` over the internal `default` net (http, not the
      // TLS hairpin); `web` must be in OPENPROJECT_ADDITIONAL__HOST__NAMES.
      environment: {
        OPENPROJECT_URL: 'http://%s:%d' % [role.WEB, webPort],
        OPENPROJECT_HTTPS: 'true',
        SECRET: '${COLLAB_SERVER_SECRET:?err}',
      },
      expose: [std.toString(hocuspocusPort)],
      ports: ['%s:%d:%d' % [reg.ips.loopback, hocuspocusPort, hocuspocusPort]],
      networks_:: lib.network.join(reg.networks.shared.postgresDB),
    },

    // Runs migrations and seeds, then exits; the long-running services wait on it.
    [role.SEEDER]: opApp {
      command: './docker/prod/seeder',
      restart: 'on-failure',
    },

    [role.WEB]: opApp {
      depends_on: [role.CACHE, role.SEEDER],
      command: './docker/prod/web',
      healthcheck: {
        test: ['CMD', 'curl', '-f', 'http://localhost:' + std.toString(webPort) + '/health_checks/default'],
        interval: '10s',
        timeout: '3s',
        retries: 3,
        start_period: '60s',
      },
      // One Puma worker instead of the default 2 — a whole forked Rails process
      // saved; low concurrency here doesn't need two. Bump back up if web slows.
      environment: opAppEnv + opAppSecrets + { WEB_CONCURRENCY: '1' },
      labels: webLabels,
      expose: [std.toString(webPort)],
      ports: ['%s:18009:%d' % [reg.ips.loopback, webPort]],
      networks_:: lib.network.join(reg.networks.shared.postgresDB),
    },

    [role.WORKER]: opApp {
      depends_on: [role.CACHE, role.SEEDER],
      command: './docker/prod/worker',
      networks_:: lib.network.join(reg.networks.shared.postgresDB),
    },
  },
  lib.network.attach(reg.networks.shared.postgresDB)
  ),
  [lib.Secret('openproject'), lib.Secret('postgres')],
)
