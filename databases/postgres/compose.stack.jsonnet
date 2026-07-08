// postgres — shared Postgres server (+ pgadmin).
//
// Owner of shared-postgres (apps join it to reach the DB) and a consumer of
// shared-db-backups (databasus owns that; postgres exposes itself on it for
// backups). Renders to compose.stack.yaml — do not edit the YAML.
//
// The db service is named `postgres_db` (the <stack>_<role> convention) and
// publishes that as its alias on every network, so consumers dial
// postgres_db:5432. That hostname is the single source in the registry
// (reg.endpoints.postgres.container.host) — change it there and this follows.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local sharedNetworks = reg.sharedNetworks;
local roles = reg.roles;

local stack = 'postgres';
local s = c.stack(stack);
local n = s.names;
local pgEndpoint = reg.endpoints.postgres;

// Host-published port for direct external access (DBeaver, psql from the LAN).
// Independent of pgEndpoint.container.port (5432) — that's the container's real
// internal listening port and is what every consumer's DATABASE_URL dials over
// shared-postgres; it must NOT be tied to whatever host port this happens to
// publish on.
local hostPort = 6109;

{
  name: stack,

  services: {
    [roles.db]: {
      local extName = pgEndpoint.container.host,
      local pgVersion = '18',

      image: 'postgres:' + pgVersion,
      container_name: pgEndpoint.container.host,  // 'postgres_db'
      volumes: [roles.db + ':/var/lib/postgresql'],
      environment: {
        // Secrets — interpolated from /dev/shm/postgres.env (parent include.env_file)
        POSTGRES_USER: '${POSTGRES_USER:?err}',
        POSTGRES_PASSWORD: '${POSTGRES_PASS:?err}',
      },
      ports: [ std.toString(hostPort) + ':5432' ],
      restart: 'always',
      networks:
      s.network.attach('default', extName) +
      s.network.attach(sharedNetworks.postgres.name, extName) +
      s.network.attach(sharedNetworks.dbBackups.name, extName),
      //   default: { aliases: [extName] },
      //   [sharedNetworks.postgres.name]: { aliases: [extName] },   // shared-postgres
      //   [sharedNetworks.dbBackups.name]: { aliases: [extName] },  // shared-db-backups
      // },
      healthcheck: {
        test: 'pg_isready -U ${POSTGRES_USER} -h localhost -d postgres',
        interval: '5s',
        timeout: '5s',
        retries: 10,
      },
    },

    // pgadmin: {
    //   local pgadminVersion = '9.13',
    // 
    // 
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
    s.network.default       // default net -> 'postgres' (private; db + pgadmin)
    + s.network.own('postgres')     // shared-postgres (owned; apps join)
    + s.network.join('dbBackups'),  // shared-db-backups (databasus owns)

  volumes: { [roles.db]: { name: n.volume(roles.db) } },
}
