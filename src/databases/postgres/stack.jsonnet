// The cluster's own identity is single-sourced at registry.endpoint.serviceGroup.postgres —
// change it there, not here. Consumers on this host reach it over shared__postgres_db;
// consumers on another host dial the published port at postgres.host.addr.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'postgres',

  db:: self.Service { role:: lib.collections.role.DB },
  dbData:: self.Volume { key:: 'db' },
};

local pg = lib.registry.endpoint.serviceGroup.postgres;
local sharedDB = lib.registry.network.shared.postgresDB;
local version = '18';

{
  compose: {
    name: refs.name,
    // shared__postgres_db is created out of band, so this stack attaches to it exactly like
    // every consumer does — nothing here owns it.
    networks: {
      default: { name: refs.name },
      [sharedDB.name]: { name: sharedDB.name, external: true },
    },
    volumes: refs.dbData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('apps', '/postgres'),

      [refs.db.key]: {
        // Other stacks already dial this name, so it is the registry's value rather than the
        // <project>_<role> convention.
        container_name: pg.container.name,
        image: 'postgres:' + version,
        restart: lib.collections.restart.always,
        depends_on: lib.secretsReady,
        networks: ['default', sharedDB.name],
        volumes: [refs.dbData.mount('/var/lib/postgresql')],
        // POSTGRES_USER and POSTGRES_PASSWORD arrive from infisical-secrets.

        // Published to the host so containers in other stacks reach it through the gateway.
        ports: ['%s:%s:%s' % [lib.collections.ip.loopback, pg.host.port, pg.container.port]],
        healthcheck: {
          // $$ escapes compose's own interpolation, so the shell in the container expands
          // the injected POSTGRES_USER rather than compose resolving it to nothing.
          test: 'pg_isready -U $$POSTGRES_USER -h localhost -d postgres',
          interval: '5s',
          timeout: '5s',
          retries: 10,
        },
      },
    },
  },
}
