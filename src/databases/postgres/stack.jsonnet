// The DB's own identity is single-sourced at reg.endpoint.postgres.container — change there,
// not here. Consumers no longer share a Docker network with this stack; they dial the
// host-published port (reg.endpoint.postgres.host) via the docker host-gateway.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'postgres';
local pg = reg.endpoint.postgres;
local pgVersion = '18';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.DB]: lib.Service {
      image: 'postgres:' + pgVersion,
      // Other stacks already dial this name; it is the registry's value, not the derived
      // <stack>_<role>, so the alias below follows it rather than the convention.
      container_name: pg.container.host,
      volumes_:: { db: '/var/lib/postgresql' },
      environment: {
        // Secrets — interpolated from /dev/shm/postgres.env (parent include.env_file)
        POSTGRES_USER: '${POSTGRES_USER:?err}',
        POSTGRES_PASSWORD: '${POSTGRES_PASS:?err}',
      },
      // Published to the host so containers in other stacks reach it via
      // host.docker.internal:<hostPort>.
      ports: [reg.ips.loopback + ":" + pg.host.port + ':' + pg.container.port],
      networks_:: lib.network.join(reg.networks.shared.postgresDB),
      restart: 'always',
      healthcheck: {
        test: 'pg_isready -U ${POSTGRES_USER} -h localhost -d postgres',
        interval: '5s',
        timeout: '5s',
        retries: 10,
      },
    },
  }, lib.network.attach(reg.networks.shared.postgresDB)),
  [lib.Secret('postgres')],
)
