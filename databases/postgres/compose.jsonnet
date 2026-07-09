// Owns shared-postgres; also sits on shared-db-backups (databasus owns) for backups.
// db hostname is single-sourced at reg.endpoints.postgres.container.host — change there, not here.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local sharedNetworks = reg.sharedNetworks;
local roles = reg.roles;

local stack = 'postgres';
local s = c.stack(stack);
local n = s.names;
local pgEndpoint = reg.endpoints.postgres;

// Host port for direct external access only — independent of pgEndpoint.container.port
// (the internal port every consumer's DATABASE_URL actually dials).
local hostPort = 6109;

local manifest = {
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
};

c.render(stack, manifest, [c.envPath.secret('postgres')])
