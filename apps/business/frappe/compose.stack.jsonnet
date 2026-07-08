// frappe — ERPNext / Frappe, single bench + multi-site (DNS-based multitenancy).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Only `frontend` joins shared-proxy (traefik owns) to be reachable; the
// rest talk to each other on the private frappe network. Runs its own MariaDB
// `db` service — no shared-postgres join.
local lib = import 'lib.libsonnet';

local stack = 'frappe';
local n = lib.compose.names(stack);
local roles = lib.registry.roles;

// Roles. `db` is the common constant (typo-safe); the rest are plain strings —
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
// Pin the immutable `version-15-<sha>` tag for max reproducibility when ready.
local image = 'ghcr.io/ktbgroup-self-hosted/frappe:version-15';
local mariadbVersion = '10.6';
local redisVersion = '7-alpine';
local maxRestartAttempts = 5;
local restart = 'on-failure:' + std.toString(maxRestartAttempts);

// Gunicorn tuning (backend). Tune GUNICORN_WORKERS to (2 * cores) + 1 on the host.
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
// each request to the matching site directory by Host header — DNS-based
// multitenancy. nginx splits /socket.io to websocket internally — never add a
// second Traefik router for it.
local frontendPort = 8080;

// frappeImageService — the fields shared by every service that runs the custom
// Frappe image (backend, configurator, frontend, queue-*, scheduler, websocket).
local frappeImageService(role) = {
  image: image,
  container_name: n.container(role),
  volumes: [n.volume('sites') + ':/home/frappe/frappe-bench/sites'],
  restart: restart,
  platform: 'linux/amd64',
  pull_policy: 'always',
  networks: { default: { aliases: [n.alias(role)] } },
};

{
  name: stack,

  services: {
    // --------------------------------------------------------------------
    // backend — Gunicorn WSGI. Serves the Frappe/ERPNext application.
    // --------------------------------------------------------------------
    [backend]: frappeImageService(backend) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      environment: {
        GUNICORN_WORKERS: std.toString(gunicornWorkers),
        GUNICORN_THREADS: std.toString(gunicornThreads),
        GUNICORN_TIMEOUT: std.toString(gunicornTimeout),
        // Secret — interpolated from /dev/shm/frappe.env (parent include.env_file).
        // Lets `bench new-site`/`bench drop-site` run via exec on this container.
        FRAPPE_DB_ROOT_PASSWORD: '${FRAPPE_DB_ROOT_PASSWORD:?err}',
      },
    },

    // --------------------------------------------------------------------
    // configurator — one-shot. Writes common_site_config.json (db + redis
    // wiring) to the shared `sites` volume. MUST finish before backend/
    // workers/scheduler/websocket start. If the stack won't come up, debug
    // this container first.
    // --------------------------------------------------------------------
    [configurator]: frappeImageService(configurator) + {
      depends_on: {
        [db]: { condition: 'service_healthy' },
        [redisCache]: { condition: 'service_started' },
        [redisQueue]: { condition: 'service_started' },
      },
      environment: {
        DB_HOST: n.alias(db),
        DB_PORT: std.toString(dbPort),
        REDIS_CACHE: n.alias(redisCache) + ':6379',
        REDIS_QUEUE: n.alias(redisQueue) + ':6379',
        SOCKETIO_PORT: std.toString(socketioPort),
      },
      command: [configuratorScript],
      entrypoint: ['bash', '-c'],
    },

    // --------------------------------------------------------------------
    // db — MariaDB. One database per site (bench new-site creates each). The
    // charset flags are required for Frappe's Unicode/emoji support.
    // --------------------------------------------------------------------
    [db]: {
      image: 'docker.io/library/mariadb:' + mariadbVersion,
      container_name: n.container(db),
      volumes: [n.volume(db) + ':/var/lib/mysql'],
      environment: {
        MARIADB_AUTO_UPGRADE: '1',
        // Secret — interpolated from /dev/shm/frappe.env (parent include.env_file)
        MYSQL_ROOT_PASSWORD: '${FRAPPE_DB_ROOT_PASSWORD:?err}',
      },
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
      networks: { default: { aliases: [n.alias(db)] } },
    },

    // --------------------------------------------------------------------
    // frontend — nginx. The ONLY service exposed to Traefik.
    // --------------------------------------------------------------------
    [frontend]: frappeImageService(frontend) + {
      depends_on: [backend, websocket],
      environment: {
        BACKEND: n.alias(backend) + ':8000',
        SOCKETIO: n.alias(websocket) + ':9000',
        // Compose interpolates environment values, so the literal $host MUST be
        // escaped as $$host (else it resolves empty and ALL routing breaks).
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
        default: { aliases: [n.alias(frontend)] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias(frontend)] },
      },
      // Single-site rule today (business.stackform.app), so proxyAdd's
      // single-Host() assumption fits. Onboarding a second tenant means this
      // stack serves multiple Hosts (DNS-based multitenancy) — at that point
      // replace this with a manual `traefik.http.routers.frappe.rule` label
      // OR-ing every site's Host() clause (proxyAdd only emits one).
      labels: lib.mixins.proxyAdd(stack, 'frappe', frontendPort, lib.registry.domains.ktbcloud),
    },

    // --------------------------------------------------------------------
    // queue-long — long + default + short queues (reports, bulk imports).
    // --------------------------------------------------------------------
    [queueLong]: frappeImageService(queueLong) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['bench', 'worker', '--queue', 'long,default,short'],
    },

    // --------------------------------------------------------------------
    // queue-short — short + default queues (emails, notifications, light jobs).
    // --------------------------------------------------------------------
    [queueShort]: frappeImageService(queueShort) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['bench', 'worker', '--queue', 'short,default'],
    },

    // --------------------------------------------------------------------
    // redis-cache — volatile cache. No persistence by design.
    // --------------------------------------------------------------------
    [redisCache]: {
      image: 'docker.io/library/redis:' + redisVersion,
      container_name: n.container(redisCache),
      restart: restart,
      expose: ['6379'],
      networks: { default: { aliases: [n.alias(redisCache)] } },
    },

    // --------------------------------------------------------------------
    // redis-queue — job queue + socketio pub/sub. Persisted so in-flight jobs
    // survive restarts.
    // --------------------------------------------------------------------
    [redisQueue]: {
      image: 'docker.io/library/redis:' + redisVersion,
      container_name: n.container(redisQueue),
      volumes: [n.volume(redisQueue) + ':/data'],
      restart: restart,
      expose: ['6379'],
      networks: { default: { aliases: [n.alias(redisQueue)] } },
    },

    // --------------------------------------------------------------------
    // scheduler — triggers timed jobs (digests, ledger aging, scheduled reports).
    // --------------------------------------------------------------------
    [scheduler]: frappeImageService(scheduler) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['bench', 'schedule'],
    },

    // --------------------------------------------------------------------
    // websocket — Socket.IO (real-time desk notifications). Internal only;
    // reached by frontend nginx at frappe-websocket:9000. Never exposed to
    // Traefik directly.
    // --------------------------------------------------------------------
    [websocket]: frappeImageService(websocket) + {
      depends_on: { [configurator]: { condition: 'service_completed_successfully' } },
      command: ['node', '/home/frappe/frappe-bench/apps/frappe/socketio.js'],
    },
  },

  volumes: {
    // sites — CRITICAL, shared by every Frappe service (no single owning role,
    // so it keeps a descriptive key rather than a bare service role). Holds
    // common_site_config.json, all per-site dirs, uploads, and backups.
    [n.volume('sites')]: { name: n.volume('sites') },
    // db — CRITICAL. MariaDB data directory. Sole volume owned by the `db` service.
    [n.volume(db)]: { name: n.volume(db) },
    // redis-queue — persists queued/in-flight jobs across restarts. Sole volume
    // owned by the `redis-queue` service.
    [n.volume(redisQueue)]: { name: n.volume(redisQueue) },
  },

  networks:
    n.network
    + lib.compose.join('proxy'),
}
