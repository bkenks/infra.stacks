// `db` is this stack's own dedicated Postgres — it does NOT join the shared cluster.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'paperless',
  envFiles:: [lib.Secret('paperless')],

  // Service keys are the upstream component names, not roles: nothing here is a generic
  // app/worker, and `webserver` is what paperless-ngx's own docs call it.
  broker:: self.Service { role:: 'broker' },
  db:: self.Service { role:: lib.collections.role.DB },
  gotenberg:: self.Service { role:: 'gotenberg' },
  tika:: self.Service { role:: 'tika' },
  webserver:: self.Service { role:: 'webserver' },

  brokerData:: self.Volume { key:: 'broker' },
  dbData:: self.Volume { key:: 'db' },
  webserverData:: self.Volume { key:: 'webserver_data' },
  webserverMedia:: self.Volume { key:: 'webserver_media' },
};

local brokerVersion = '8';
local dbVersion = '18';
local gotenbergVersion = '8.25';
local tikaVersion = 'latest';
local paperlessVersion = 'latest';

local webPort = '8000';
local dbUser = refs.name;
local dbName = refs.name;

local bindRoot = lib.collections.dirs.docker.bindMounts + '/apps/paperless';
local sharedDB = lib.registry.network.shared.paperlessDB;

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [sharedDB.name]: { name: sharedDB.name, external: true },
    },
    volumes: refs.brokerData.declare + refs.dbData.declare
             + refs.webserverData.declare + refs.webserverMedia.declare,

    services: {
      [refs.broker.key]: {
        container_name: refs.broker.ext,
        image: 'docker.io/library/redis:' + brokerVersion,
        restart: lib.collections.restart.onFailure(5),
        volumes: [refs.brokerData.mount('/data')],
        environment: {
          ALLOW_EMPTY_PASSWORD: 'yes',
        },
        healthcheck: {
          test: ['CMD', 'redis-cli', 'ping'],
          interval: '10s',
          timeout: '5s',
          retries: 5,
        },
        expose: ['6379'],
      },

      [refs.db.key]: {
        container_name: refs.db.ext,
        image: 'docker.io/library/postgres:' + dbVersion,
        restart: lib.collections.restart.onFailure(5),
        networks: ['default', sharedDB.name],
        volumes: [refs.dbData.mount('/var/lib/postgresql')],
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
          POSTGRES_PASSWORD: '${PAPERLESS_PG_PASS:?err}',
        },
        healthcheck: {
          test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
          interval: '5s',
          timeout: '10s',
          retries: 10,
        },
        expose: ['5432'],
        ports: ['%s:18025:5432' % lib.collections.ip.loopback],
      },

      [refs.gotenberg.key]: {
        container_name: refs.gotenberg.ext,
        image: 'docker.io/gotenberg/gotenberg:' + gotenbergVersion,
        restart: lib.collections.restart.onFailure(5),
        // The chromium route converts .eml files; disallow tracking pixels/javascript.
        command: ['gotenberg', '--chromium-disable-javascript=true', '--chromium-allow-list=file:///tmp/.*'],
        expose: ['3000'],
      },

      [refs.tika.key]: {
        container_name: refs.tika.ext,
        image: 'docker.io/apache/tika:' + tikaVersion,
        restart: lib.collections.restart.onFailure(5),
        expose: ['9998'],
      },

      [refs.webserver.key]: {
        container_name: refs.webserver.ext,
        image: 'ghcr.io/paperless-ngx/paperless-ngx:' + paperlessVersion,
        restart: lib.collections.restart.onFailure(5),
        depends_on: {
          [refs.broker.key]: { condition: lib.collections.condition.healthy },
          [refs.db.key]: { condition: lib.collections.condition.healthy },
          [refs.gotenberg.key]: { condition: lib.collections.condition.started },
          [refs.tika.key]: { condition: lib.collections.condition.started },
        },
        volumes: [
          refs.webserverData.mount('/usr/src/paperless/data'),
          refs.webserverMedia.mount('/usr/src/paperless/media'),
          bindRoot + '/export:/usr/src/paperless/export',
          bindRoot + '/consume:/usr/src/paperless/consume',
        ],
        environment: {
          PAPERLESS_TIKA_ENABLED: '1',
          PAPERLESS_OCR_LANGUAGE: 'eng',

          PAPERLESS_URL: 'https://paper.' + lib.collections.domain.ktbinternal,
          PAPERLESS_TIME_ZONE: 'America/New_York',
          PAPERLESS_DATE_ORDER: 'MDY',

          PAPERLESS_REDIS: 'redis://%s:6379' % refs.broker.key,
          PAPERLESS_TIKA_GOTENBERG_ENDPOINT: 'http://%s:3000' % refs.gotenberg.key,
          PAPERLESS_TIKA_ENDPOINT: 'http://%s:9998' % refs.tika.key,

          PAPERLESS_DBHOST: refs.db.key,
          PAPERLESS_DBUSER: dbUser,
          PAPERLESS_DBNAME: dbName,
          PAPERLESS_DBPASS: '${PAPERLESS_PG_PASS:?err}',
          PAPERLESS_SECRET_KEY: '${PAPERLESS_SECRET_KEY:?err}',
        },
        healthcheck: {
          test: ['CMD', 'curl', '-fs', '-S', '--max-time', '2', 'http://localhost:' + webPort],
          interval: '30s',
          timeout: '10s',
          retries: 5,
        },
        expose: [webPort],
        ports: ['%s:18010:%s' % [lib.collections.ip.loopback, webPort]],
      },
    },
  },
}
