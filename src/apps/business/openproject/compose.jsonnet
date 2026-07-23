// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local c = import 'lib/compose.libsonnet';
local reg = import 'lib/registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'openproject';
local s = c.stack(stack);
local n = s.names;
local pgHost = reg.endpoints.postgres.host.host;  // 'host.docker.internal'
local pgPort = reg.endpoints.postgres.host.port;  // 6109

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

local opApp = {
  image: 'openproject/openproject:' + appVersion,
  volumes: [
    n.volume('assets') + ':/var/openproject/assets',
    './token/enterprise_token.rb:/app/app/models/enterprise_token.rb',
  ],
  restart: 'unless-stopped',
};

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
  OPENPROJECT_ADDITIONAL__HOST__NAMES: '[' + cloudDomain + ', ' + internalDomain + ', web' + ']',
  OPENPROJECT_URL: 'https://' + cloudDomain,
  OPENPROJECT_COLLABORATIVE__EDITING__HOCUSPOCUS__URL: 'wss://' + cloudDomain + '/hocuspocus',
  OPENPROJECT_RAILS__CACHE__STORE: 'memcache',
  OPENPROJECT_CACHE__MEMCACHE__SERVER: 'cache:11211',
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

local webLabels = { autoheal: 'true' };

local manifest = {
  name: stack,

  services: {
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
      extra_hosts: ['host.docker.internal:host-gateway'],
      networks: {
        default: { aliases: [n.container('cron')] },
      },
    },
    hocuspocus: {
      image: 'openproject/hocuspocus:' + hocuspocusVersion,
      container_name: n.container('hocuspocus'),
      restart: 'unless-stopped',
      // Calls back into `web` over the internal `default` net (http, not the
      // TLS hairpin); `web` must be in OPENPROJECT_ADDITIONAL__HOST__NAMES.
      environment: {
        OPENPROJECT_URL: 'http://web:8080',
        OPENPROJECT_HTTPS: 'true',
        SECRET: '${COLLAB_SERVER_SECRET:?err}',
      },
      expose: [std.toString(hocuspocusPort)],
      networks: {
        default: { aliases: [n.container('hocuspocus')] },
      },
    } + c.publish(1234, hocuspocusPort),

    seeder: opApp + {
      container_name: n.container('seeder'),
      command: './docker/prod/seeder',
      restart: 'on-failure',
      environment: opAppEnv + opAppSecrets,
      extra_hosts: ['host.docker.internal:host-gateway'],
      networks: {
        default: { aliases: [n.container('seeder')] },
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
      // One Puma worker instead of the default 2 — a whole forked Rails process
      // saved; low concurrency here doesn't need two. Bump back up if web slows.
      environment: opAppEnv + opAppSecrets + { WEB_CONCURRENCY: '1' },
      labels: webLabels,
      expose: [std.toString(webPort)],
      extra_hosts: ['host.docker.internal:host-gateway'],
      networks: {
        default: { aliases: [n.container('web')] },
      },
    } + c.publish(18009, webPort),

    worker: opApp + {
      container_name: n.container('worker'),
      depends_on: ['cache', 'seeder'],
      command: './docker/prod/worker',
      environment: opAppEnv + opAppSecrets,
      extra_hosts: ['host.docker.internal:host-gateway'],
      networks: {
        default: { aliases: [n.container('worker')] },
      },
    },
  },

  volumes: { [n.volume('assets')]: { name: n.volume('assets') } },

  networks:
    s.network.default,
};

c.render(stack, manifest, [secrets.openproject.path, secrets.postgres.path])
