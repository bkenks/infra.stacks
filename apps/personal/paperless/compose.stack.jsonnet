// paperless — Paperless-ngx document management, with its
// own dedicated Postgres + Redis (broker) + Gotenberg + Apache Tika for
// office-document consumption.
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Only `webserver` is Traefik-facing; it joins shared-proxy (traefik
// owns). `db` is this stack's OWN dedicated Postgres — it does NOT join
// shared-postgres.
//
// Volume names follow the standard KTB convention (n.volume(...)) — this was
// previously pinned to the pre-jsonnet layout (`paperless-production_*`) to
// avoid a rename; that pin is now dropped as part of the naming-convention
// pass, so existing volumes must be migrated/renamed on next deploy.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'paperless';
local s = c.stack(stack);
local n = s.names;
local broker = 'broker';
local db = reg.roles.db;
local gotenberg = 'gotenberg';
local tika = 'tika';
local webserver = 'webserver';

local brokerVersion = '8';           // docker.io/library/redis
local dbVersion = '18';              // docker.io/library/postgres
local gotenbergVersion = '8.25';     // docker.io/gotenberg/gotenberg
local tikaVersion = 'latest';        // docker.io/apache/tika
local paperlessVersion = 'latest';   // ghcr.io/paperless-ngx/paperless-ngx

local webPort = 8000;
local dbUser = 'paperless';
local dbName = 'paperless';

// Two extra bind mounts (not named volumes) on webserver, under the shared
// host bind-mount root.
local exportMount = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/paperless/export';
local consumeMount = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/paperless/consume';

// Volume resource keys. broker/db each own exactly one volume, so the key is
// just the service's own role (broker/db); webserver owns two, so its keys
// get a '_<purpose>' suffix.
local dataVol = webserver + '_data';
local mediaVol = webserver + '_media';

{
  name: stack,

  services: {
    [broker]: {
      image: 'docker.io/library/redis:' + brokerVersion,
      container_name: n.container(broker),
      volumes: [broker + ':/data'],
      environment: {
        ALLOW_EMPTY_PASSWORD: 'yes',
      },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD', 'redis-cli', 'ping'],
        interval: '10s',
        timeout: '5s',
        retries: 5,
      },
      networks: { default: { aliases: [n.container(broker)] } },
      expose: ['6379'],
    },

    [db]: {
      image: 'docker.io/library/postgres:' + dbVersion,
      container_name: n.container(db),
      volumes: [db + ':/var/lib/postgresql'],
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        // Secret — interpolated from /dev/shm/paperless.env (parent include.env_file)
        POSTGRES_PASSWORD: '${PAPERLESS_PG_PASS:?err}',
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

    [gotenberg]: {
      image: 'docker.io/gotenberg/gotenberg:' + gotenbergVersion,
      container_name: n.container(gotenberg),
      // The gotenberg chromium route converts .eml files. Disallow external
      // content like tracking pixels or javascript.
      command: ['gotenberg', '--chromium-disable-javascript=true', '--chromium-allow-list=file:///tmp/.*'],
      restart: 'on-failure:5',
      networks: { default: { aliases: [n.container(gotenberg)] } },
      expose: ['3000'],
    },

    [tika]: {
      image: 'docker.io/apache/tika:' + tikaVersion,
      container_name: n.container(tika),
      restart: 'on-failure:5',
      networks: { default: { aliases: [n.container(tika)] } },
      expose: ['9998'],
    },

    [webserver]: {
      image: 'ghcr.io/paperless-ngx/paperless-ngx:' + paperlessVersion,
      container_name: n.container(webserver),
      depends_on: {
        [broker]: { condition: 'service_healthy' },
        [db]: { condition: 'service_healthy' },
        [gotenberg]: { condition: 'service_started' },
        [tika]: { condition: 'service_started' },
      },
      volumes: [
        dataVol + ':/usr/src/paperless/data',
        mediaVol + ':/usr/src/paperless/media',
        exportMount + ':/usr/src/paperless/export',
        consumeMount + ':/usr/src/paperless/consume',
      ],
      environment: {
        // --- Document processing ---
        PAPERLESS_TIKA_ENABLED: '1',
        PAPERLESS_OCR_LANGUAGE: 'eng',

        // --- Locale ---
        PAPERLESS_URL: 'https://paper.' + reg.domains.ktbinternal,
        PAPERLESS_TIME_ZONE: 'America/New_York',
        PAPERLESS_DATE_ORDER: 'MDY',

        // --- Service endpoints (reached on this stack's private network) ---
        PAPERLESS_REDIS: 'redis://' + n.container(broker) + ':6379',
        PAPERLESS_TIKA_GOTENBERG_ENDPOINT: 'http://' + n.container(gotenberg) + ':3000',
        PAPERLESS_TIKA_ENDPOINT: 'http://' + n.container(tika) + ':9998',

        // --- Database ---
        PAPERLESS_DBHOST: n.container(db),
        PAPERLESS_DBUSER: dbUser,
        PAPERLESS_DBNAME: dbName,
        // Secrets — interpolated from /dev/shm/paperless.env (parent include.env_file)
        PAPERLESS_DBPASS: '${PAPERLESS_PG_PASS:?err}',
        PAPERLESS_SECRET_KEY: '${PAPERLESS_SECRET_KEY:?err}',
      },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD', 'curl', '-fs', '-S', '--max-time', '2', 'http://localhost:' + std.toString(webPort)],
        interval: '30s',
        timeout: '10s',
        retries: 5,
      },
      networks: {
        default: { aliases: [n.container(webserver)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(webserver)] },
      },
      // Exposed to Traefik on shared-proxy — no published host port.
      labels: s.proxy.add(stack, 'paper', webPort),
      expose: [std.toString(webPort)],
    },
  },

  volumes: {
    [broker]: { name: n.volume(broker) },
    [db]: { name: n.volume(db) },
    [dataVol]: { name: n.volume(dataVol) },
    [mediaVol]: { name: n.volume(mediaVol) },
  },

  networks:
    s.network.default
    + s.network.join('proxy'),
}
