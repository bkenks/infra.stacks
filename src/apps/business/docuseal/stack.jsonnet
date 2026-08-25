local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'docuseal',
  // The shared Postgres credentials come from the postgres bundle, not this stack's.
  envFiles:: [lib.Secret('docuseal'), lib.Secret('postgres')],

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
};

local version = '2.5.3';
local port = '3000';
local pg = lib.registry.endpoint.serviceGroup.postgres;
local sharedDB = lib.registry.network.shared.postgresDB;

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
    volumes: refs.appData.declare,

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'docuseal/docuseal:' + version,
        restart: lib.collections.restart.onFailure(5),
        networks: ['default', sharedDB.name],
        volumes: [refs.appData.mount('/data/docuseal')],
        environment: {
          PORT: port,
          // Also the SSL switch: forces HTTPS redirects + absolute signing-link URLs.
          FORCE_SSL: refs.name + '.' + lib.collections.domain.ktbcloud,
          DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@%s/docuseal'
                        % pg.container.addr,
          SECRET_KEY_BASE: '${DOCUSEAL_SECRET_KEY_BASE:?err}',
        },
        expose: [port],
        ports: ['%s:18002:%s' % [lib.collections.ip.loopback, port]],
      },
    },
  },
}
