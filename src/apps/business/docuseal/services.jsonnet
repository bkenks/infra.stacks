local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = '2.5.3';
local port = '3000';
local pg = lib.registry.endpoint.serviceGroup.postgres;
local sharedDB = lib.registry.network.shared.postgresDB;

{
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
}
