local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = '2.5.3';
local port = '3000';
local pg = lib.registry.endpoint.postgres;
local sharedDB = lib.registry.networks.shared.postgresDB;

{
  name: refs.name,
  networks: refs.networks + sharedDB.attach,
  volumes: refs.appData.declare,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'docuseal/docuseal:' + version,
      restart: lib.restart.onFailure(5),
      networks: ['default', sharedDB.name],
      volumes: [refs.appData.mount('/data/docuseal')],
      environment: {
        PORT: port,
        // Also the SSL switch: forces HTTPS redirects + absolute signing-link URLs.
        FORCE_SSL: refs.name + '.' + lib.domain.ktbcloud,
        DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@%s/docuseal'
                      % pg.container.addr,
        SECRET_KEY_BASE: '${DOCUSEAL_SECRET_KEY_BASE:?err}',
      },
      expose: [port],
      extra_hosts: lib.hostGateway.extraHosts,
      ports: ['%s:18002:%s' % [lib.ip.loopback, port]],
    },
  },
}
