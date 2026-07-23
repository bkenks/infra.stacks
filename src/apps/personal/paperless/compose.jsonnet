// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML. `db` is this stack's
// own dedicated Postgres — does NOT join shared-postgres.
//
// Volumes are declared as `volumes_` on the service that mounts them; lib.Stack registers
// each one as <stack>_<key> — migrate/rename existing volumes on next deploy.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'paperless';
local broker = 'broker';
local gotenberg = 'gotenberg';
local tika = 'tika';
local webserver = 'webserver';

local brokerVersion = '8';
local dbVersion = '18';
local gotenbergVersion = '8.25';
local tikaVersion = 'latest';
local paperlessVersion = 'latest';

local webPort = 8000;
local dbUser = 'paperless';
local dbName = 'paperless';

local exportMount = reg.dirs.docker.root + reg.dirs.docker.bindMounts + '/apps/paperless/export';
local consumeMount = reg.dirs.docker.root + reg.dirs.docker.bindMounts + '/apps/paperless/consume';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [broker]: lib.Service {
      image: 'docker.io/library/redis:' + brokerVersion,
      volumes_:: { broker: '/data' },
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
      expose: ['6379'],
    },

    [role.DB]: lib.Service {
      image: 'docker.io/library/postgres:' + dbVersion,
      volumes_:: { db: '/var/lib/postgresql' },
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        POSTGRES_PASSWORD: '${PAPERLESS_PG_PASS:?err}',
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

    [gotenberg]: lib.Service {
      image: 'docker.io/gotenberg/gotenberg:' + gotenbergVersion,
      // Chromium route converts .eml files; disallow tracking pixels/javascript.
      command: ['gotenberg', '--chromium-disable-javascript=true', '--chromium-allow-list=file:///tmp/.*'],
      restart: 'on-failure:5',
      expose: ['3000'],
    },

    [tika]: lib.Service {
      image: 'docker.io/apache/tika:' + tikaVersion,
      restart: 'on-failure:5',
      expose: ['9998'],
    },

    [webserver]: lib.Service {
      image: 'ghcr.io/paperless-ngx/paperless-ngx:' + paperlessVersion,
      depends_on: {
        [broker]: { condition: 'service_healthy' },
        [role.DB]: { condition: 'service_healthy' },
        [gotenberg]: { condition: 'service_started' },
        [tika]: { condition: 'service_started' },
      },
      volumes_:: {
        webserver_data: '/usr/src/paperless/data',
        webserver_media: '/usr/src/paperless/media',
      },
      mounts_:: [
        exportMount + ':/usr/src/paperless/export',
        consumeMount + ':/usr/src/paperless/consume',
      ],
      environment: {
        PAPERLESS_TIKA_ENABLED: '1',
        PAPERLESS_OCR_LANGUAGE: 'eng',

        PAPERLESS_URL: 'https://paper.' + reg.domains.ktbinternal,
        PAPERLESS_TIME_ZONE: 'America/New_York',
        PAPERLESS_DATE_ORDER: 'MDY',

        PAPERLESS_REDIS: 'redis://' + ref[broker] + ':6379',
        PAPERLESS_TIKA_GOTENBERG_ENDPOINT: 'http://' + ref[gotenberg] + ':3000',
        PAPERLESS_TIKA_ENDPOINT: 'http://' + ref[tika] + ':9998',

        PAPERLESS_DBHOST: ref[role.DB],
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
      expose: [std.toString(webPort)],
      ports: ['%s:18010:%s' % [reg.ips.loopback, webPort]],
    },
  }),
  [lib.Secret('paperless')],
)
