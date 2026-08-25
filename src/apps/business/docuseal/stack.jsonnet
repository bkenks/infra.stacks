local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'docuseal',

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
};

local version = '2.5.3';
local port = '3000';
local sharedDB = lib.registry.network.shared.postgresDB;

{
  compose: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [sharedDB.name]: { name: sharedDB.name, external: true },
    },
    volumes: refs.appData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('apps', '/docuseal'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'docuseal/docuseal:' + version,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        networks: ['default', sharedDB.name],
        volumes: [refs.appData.mount('/data/docuseal')],
        // DATABASE_URL and SECRET_KEY_BASE arrive from infisical-secrets. DATABASE_URL is
        // stored whole rather than assembled here: the provider injects values, and there
        // is no compose-level interpolation left to build a URL out of its parts.
        environment: {
          PORT: port,
          // Also the SSL switch: forces HTTPS redirects + absolute signing-link URLs.
          FORCE_SSL: refs.name + '.' + lib.collections.domain.ktbcloud,
        },
        expose: [port],
        ports: ['%s:18002:%s' % [lib.collections.ip.loopback, port]],
      },
    },
  },
}
