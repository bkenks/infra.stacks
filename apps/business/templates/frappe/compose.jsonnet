// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'frappe';
local s = c.stack(stack);
local n = s.names;
local roles = reg.roles;

// `db` is the typo-safe registry constant; the rest are plain strings since
// frappe has two redis instances (cache/queue) so there's no single `roles.redis`.
local db = roles.db;
local backend = 'backend';
local configurator = 'configurator';
local frontend = 'frontend';
local queueLong = 'queue-long';
local queueShort = 'queue-short';
local redisCache = 'redis-cache';
local redisQueue = 'redis-queue';
local scheduler = 'scheduler';
local websocket = 'websocket';

// Custom image (built from image/apps.json -> GHCR; see image/README.md).
local image = 'ghcr.io/ktbgroup-self-hosted/frappe:version-15';
local mariadbVersion = '10.6';
local redisVersion = '7-alpine';
local maxRestartAttempts = 5;
local restart = 'on-failure:' + std.toString(maxRestartAttempts);

// Tune GUNICORN_WORKERS to (2 * cores) + 1 on the host.
local gunicornWorkers = 2;
local gunicornThreads = 4;
local gunicornTimeout = 120;

// configurator writes these into common_site_config.json on the shared `sites`
// volume, which every Frappe service reads.
local dbPort = 3306;
local socketioPort = 9000;
local configuratorScript =
  'ls -1 apps > sites/apps.txt; ' +
  'bench set-config -g db_host $$DB_HOST; ' +
  'bench set-config -gp db_port $$DB_PORT; ' +
  'bench set-config -g redis_cache "redis://$$REDIS_CACHE"; ' +
  'bench set-config -g redis_queue "redis://$$REDIS_QUEUE"; ' +
  'bench set-config -g redis_socketio "redis://$$REDIS_QUEUE"; ' +
  'bench set-config -gp socketio_port $$SOCKETIO_PORT;';

// The only service exposed to Traefik. FRAPPE_SITE_NAME_HEADER ($$host) routes
// each request to the matching site by Host header (DNS-based multitenancy).
// nginx splits /socket.io to websocket internally — never add a second
// Traefik router for it.
local frontendPort = 8080;

local frappeImageService(role) = {
  image: image,
  container_name: n.container(role),
  volumes: [n.volume('sites') + ':/home/frappe/frappe-bench/sites'],
  restart: restart,
  platform: 'linux/amd64',
  pull_policy: 'always',
  networks: { default: { aliases: [n.container(role)] } },
};

local manifest = {
  name: stack,

  services: {
    [backend]: frappeImageService(backend) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      environment: {
        GUNICORN_WORKERS: std.toString(gunicornWorkers),
        GUNICORN_THREADS: std.toString(gunicornThreads),
        GUNICORN_TIMEOUT: std.toString(gunicornTimeout),
        // Lets `bench new-site`/`bench drop-site` run via exec on this container.
        FRAPPE_DB_ROOT_PASSWORD: '${FRAPPE_DB_ROOT_PASSWORD:?err}',
      },
    },

    // MUST finish before backend/workers/scheduler/websocket start — if the
    // stack won't come up, debug this container first.
    [configurator]: frappeImageService(configurator) + {
      depends_on: {
        [db]: { condition: 'service_healthy' },
        [redisCache]: { condition: 'service_started' },
        [redisQueue]: { condition: 'service_started' },
      },
      environment: {
        DB_HOST: n.container(db),
        DB_PORT: std.toString(dbPort),
        REDIS_CACHE: n.container(redisCache) + ':6379',
        REDIS_QUEUE: n.container(redisQueue) + ':6379',
        SOCKETIO_PORT: std.toString(socketioPort),
      },
      command: [configuratorScript],
      entrypoint: ['bash', '-c'],
    },

    [db]: {
      image: 'docker.io/library/mariadb:' + mariadbVersion,
      container_name: n.container(db),
      volumes: [n.volume(db) + ':/var/lib/mysql'],
      environment: {
        MARIADB_AUTO_UPGRADE: '1',
        MYSQL_ROOT_PASSWORD: '${FRAPPE_DB_ROOT_PASSWORD:?err}',
      },
      // Charset flags required for Frappe's Unicode/emoji support.
      command: [
        '--character-set-server=utf8mb4',
        '--collation-server=utf8mb4_unicode_ci',
        '--skip-character-set-client-handshake',
      ],
      restart: restart,
      healthcheck: {
        test: ['CMD', 'healthcheck.sh', '--connect', '--innodb_initialized'],
        interval: '5s',
        timeout: '5s',
        retries: 10,
        start_period: '15s',
      },
      expose: ['3306'],
      networks: { default: { aliases: [n.container(db)] } },
    },

    [frontend]: frappeImageService(frontend) + {
      depends_on: [backend, websocket],
      environment: {
        BACKEND: n.container(backend) + ':8000',
        SOCKETIO: n.container(websocket) + ':9000',
        // Compose interpolates env values, so the literal $host MUST be escaped
        // as $$host (else it resolves empty and ALL routing breaks).
        FRAPPE_SITE_NAME_HEADER: '$$host',
        // Traefik terminates TLS and forwards over the proxy network; trust its
        // range so Frappe logs the real client IP. 172.16.0.0/12 covers Docker
        // bridge networks.
        UPSTREAM_REAL_IP_ADDRESS: '172.16.0.0/12',
        UPSTREAM_REAL_IP_HEADER: 'X-Forwarded-For',
        UPSTREAM_REAL_IP_RECURSIVE: 'on',
        PROXY_READ_TIMEOUT: std.toString(gunicornTimeout),
        CLIENT_MAX_BODY_SIZE: '50m',
      },
      command: ['nginx-entrypoint.sh'],
      expose: [std.toString(frontendPort)],
      networks: {
        default: { aliases: [n.container(frontend)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(frontend)] },
      },
      // Single-site rule today, so proxyAdd's single-Host() assumption fits. A
      // second tenant needs a manual multi-Host() router label (proxyAdd only
      // emits one).
      labels: s.proxy.add(stack, 'frappe', frontendPort, reg.domains.ktbinternal),
    },

    [queueLong]: frappeImageService(queueLong) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['bench', 'worker', '--queue', 'long,default,short'],
    },

    [queueShort]: frappeImageService(queueShort) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['bench', 'worker', '--queue', 'short,default'],
    },

    // No persistence by design.
    [redisCache]: {
      image: 'docker.io/library/redis:' + redisVersion,
      container_name: n.container(redisCache),
      restart: restart,
      expose: ['6379'],
      networks: { default: { aliases: [n.container(redisCache)] } },
    },

    // Persisted so in-flight jobs survive restarts.
    [redisQueue]: {
      image: 'docker.io/library/redis:' + redisVersion,
      container_name: n.container(redisQueue),
      volumes: [n.volume(redisQueue) + ':/data'],
      restart: restart,
      expose: ['6379'],
      networks: { default: { aliases: [n.container(redisQueue)] } },
    },

    [scheduler]: frappeImageService(scheduler) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['bench', 'schedule'],
    },

    // Internal only — reached by frontend nginx at frappe-websocket:9000.
    // Never exposed to Traefik directly.
    [websocket]: frappeImageService(websocket) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['node', '/home/frappe/frappe-bench/apps/frappe/socketio.js'],
    },
  },

  volumes: {
    // CRITICAL — shared by every Frappe service (no single owning role, hence
    // the descriptive key). Holds common_site_config.json, per-site dirs,
    // uploads, and backups.
    [n.volume('sites')]: { name: n.volume('sites') },
    // CRITICAL — MariaDB data directory.
    [n.volume(db)]: { name: n.volume(db) },
    [n.volume(redisQueue)]: { name: n.volume(redisQueue) },
  },

  networks:
    s.network.default
    + s.network.join('proxy'),
};

c.render(stack, manifest, [c.envPath.secret('frappe.env')])
