// postgres — shared Postgres server (+ pgadmin).
//
// Owner of shared-postgres (apps join it to reach the DB) and a consumer of
// shared-db-backups (databasus owns that; postgres exposes itself on it for
// backups). Renders to compose.stack.yaml — do not edit the YAML.
//
// The db service is named `postgres_db` (the <stack>_<role> convention) and
// publishes that as its alias on every network, so consumers dial
// postgres_db:5432. That hostname is the single source in the registry
// (reg.endpoints.postgres.private.host) — change it there and this follows.
local lib = import 'lib.libsonnet';

local stack = 'postgres';
local n = lib.compose.names(stack);
local roles = lib.registry.roles;
local addr = lib.registry.endpoints.postgres.private.host;  // 'postgres_db' — container_name + network alias (registry SoT)
local pgVersion = '18';
// local pgadminVersion = '9.13';

{
  name: stack,

  services: {
    [roles.db]: {
      image: 'postgres:' + pgVersion,
      container_name: addr,  // 'postgres_db'
      volumes: [roles.db + ':/var/lib/postgresql'],
      environment: {
        // Secrets — interpolated from /dev/shm/postgres.env (parent include.env_file)
        POSTGRES_USER: '${POSTGRES_USER:?err}',
        POSTGRES_PASSWORD: '${POSTGRES_PASS:?err}',
      },
      ports: [ '6109:5432' ],
      restart: 'always',
      networks: {
        default: { aliases: [addr] },
        [lib.registry.sharedNetworks.postgres.name]: { aliases: [addr] },   // shared-postgres
        [lib.registry.sharedNetworks.dbBackups.name]: { aliases: [addr] },  // shared-db-backups
      },
      healthcheck: {
        test: 'pg_isready -U ${POSTGRES_USER} -h localhost -d postgres',
        interval: '5s',
        timeout: '5s',
        retries: 10,
      },
    },

    // pgadmin: {
    //   image: 'dpage/pgadmin4:' + pgadminVersion,
    //   container_name: n.container('admin'),  // 'postgres_admin'
    //   ports: ['5050:80'],
    //   environment: {
    //     PGADMIN_DEFAULT_EMAIL: 'briankenkel.t@gmail.com',
    //     // Secret — interpolated from /dev/shm/postgres.env (parent include.env_file)
    //     PGADMIN_DEFAULT_PASSWORD: '${PG_ADMIN_PASS:?err}',
    //     PGADMIN_CONFIG_SERVER_MODE: 'True',
    //     PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: 'True',
    //   },
    //   networks: { default: {} },
    // },
  },

  networks:
    n.network       // default net -> 'postgres' (private; db + pgadmin)
    + lib.compose.own('postgres')     // shared-postgres (owned; apps join)
    + lib.compose.join('dbBackups'),  // shared-db-backups (databasus owns)

  volumes: { [roles.db]: { name: n.volume(roles.db) } },
}
