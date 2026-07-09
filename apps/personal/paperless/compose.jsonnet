// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML. `db` is this stack's
// own dedicated Postgres — does NOT join shared-postgres.
//
// Volume names follow the standard n.volume() convention — migrate/rename
// existing volumes on next deploy.
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

local brokerVersion = '8';
local dbVersion = '18';
local gotenbergVersion = '8.25';
local tikaVersion = 'latest';
local paperlessVersion = 'latest';

local webPort = 8000;
local dbUser = 'paperless';
local dbName = 'paperless';

local exportMount = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/paperless/export';
local consumeMount = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/paperless/consume';

local dataVol = webserver + '_data';
local mediaVol = webserver + '_media';

local manifest = {
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
      // Chromium route converts .eml files; disallow tracking pixels/javascript.
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
        PAPERLESS_TIKA_ENABLED: '1',
        PAPERLESS_OCR_LANGUAGE: 'eng',

        PAPERLESS_URL: 'https://paper.' + reg.domains.ktbinternal,
        PAPERLESS_TIME_ZONE: 'America/New_York',
        PAPERLESS_DATE_ORDER: 'MDY',

        PAPERLESS_REDIS: 'redis://' + n.container(broker) + ':6379',
        PAPERLESS_TIKA_GOTENBERG_ENDPOINT: 'http://' + n.container(gotenberg) + ':3000',
        PAPERLESS_TIKA_ENDPOINT: 'http://' + n.container(tika) + ':9998',

        PAPERLESS_DBHOST: n.container(db),
        PAPERLESS_DBUSER: dbUser,
        PAPERLESS_DBNAME: dbName,
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
};

c.render(stack, manifest, [c.envPath.secret('paperless')])
