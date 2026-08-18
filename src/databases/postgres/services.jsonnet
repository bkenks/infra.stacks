// The cluster's own identity is single-sourced at registry.endpoint.postgres — change it
// there, not here. Consumers no longer share a docker network with this stack; they dial
// the host-published port through the docker gateway.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local pg = lib.registry.endpoint.postgres;
local sharedDB = lib.registry.networks.shared.postgresDB;
local version = '18';

{
  name: refs.name,
  // shared__postgres_db is created out of band, so this stack attaches to it exactly like
  // every consumer does — nothing here owns it.
  networks: refs.networks + sharedDB.attach,
  volumes: refs.dbData.declare,

  services: {
    [refs.db.key]: {
      // Other stacks already dial this name, so it is the registry's value rather than the
      // <project>_<role> convention.
      container_name: pg.container.host,
      image: 'postgres:' + version,
      restart: lib.restart.always,
      networks: ['default', sharedDB.name],
      volumes: [refs.dbData.mount('/var/lib/postgresql')],
      environment: {
        POSTGRES_USER: '${POSTGRES_USER:?err}',
        POSTGRES_PASSWORD: '${POSTGRES_PASS:?err}',
      },
      // Published to the host so containers in other stacks reach it through the gateway.
      ports: ['%s:%s:%s' % [lib.ip.loopback, pg.host.port, pg.container.port]],
      healthcheck: {
        test: 'pg_isready -U ${POSTGRES_USER} -h localhost -d postgres',
        interval: '5s',
        timeout: '5s',
        retries: 10,
      },
    },
  },
}
