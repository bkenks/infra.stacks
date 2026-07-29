// Compiles to compose.yaml and stack.services.yaml — do not edit the YAML.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'invoice-shelf';
local version = 'latest';
local appPort = 8080;
local hostPort = 18021;

// Shared cluster, dialled through the docker host-gateway.
local pgHost = reg.endpoint.postgres.host.host;  // 'host.docker.internal'
local pgPort = reg.endpoint.postgres.host.port;  // '6109'
local dbName = 'invoiceshelf';

local fqdn = 'invoiceshelf.' + reg.domains.ktbinternal;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'invoiceshelf/invoiceshelf:' + version,
      volumes_:: {
        app_storage: '/var/www/html/storage/',
        app_modules: '/var/www/html/Modules/',
      },
      environment: {
        APP_NAME: 'InvoiceShelf',
        APP_ENV: 'production',
        APP_DEBUG: 'false',
        // Laravel builds absolute URLs and cookie scope from these three, so they must
        // match the public origin exactly or login POSTs come back 419.
        APP_URL: 'https://' + fqdn,
        SESSION_DOMAIN: fqdn,
        SANCTUM_STATEFUL_DOMAINS: fqdn,

        DB_CONNECTION: 'pgsql',
        DB_HOST: pgHost,
        DB_PORT: pgPort,
        DB_DATABASE: dbName,
        DB_USERNAME: '${POSTGRES_USER:?err}',
        DB_PASSWORD: '${POSTGRES_PASS:?err}',

        CACHE_STORE: 'file',
        SESSION_DRIVER: 'file',
        SESSION_LIFETIME: '240',
        AUTORUN_ENABLED: 'true',
        AUTORUN_LARAVEL_MIGRATION: 'false',
        AUTORUN_LARAVEL_OPTIMIZE: 'false',
        PHP_OPCACHE_ENABLE: '1',
      },
      extra_hosts: ['host.docker.internal:host-gateway'],
      expose: [std.toString(appPort)],
      ports: ['%s:%d:%d' % [reg.ips.loopback, hostPort, appPort]],
    },
  }),
  [lib.Secret('postgres')],
)
