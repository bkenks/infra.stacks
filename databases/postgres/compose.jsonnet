// postgres — shared Postgres server (+ pgadmin).
//
// Owner of shared-postgres (apps join it to reach the DB) and a consumer of
// shared-db-backups (databasus owns that; postgres exposes itself on it for
// backups). Renders to compose.yaml — do not edit the YAML.
//
// The db service keeps the alias `postgres` on every network, so consumer
// connection strings (postgres:5432) are unchanged by the network rename.
local infra = import 'infra.libsonnet';

local stack = 'postgres';
local alias = 'postgres';  // hostname apps dial — must match reg.endpoints.postgres.host
local pgVersion = '18';
local pgadminVersion = '9.13';

{
  name: stack,

  services: {
    db: {
      image: 'postgres:' + pgVersion,
      profiles: ['full', 'no_pgadmin'],
      volumes: ['db:/var/lib/postgresql'],
      environment: {
        // Secrets — interpolated from /dev/shm/postgres.env (parent include.env_file)
        POSTGRES_USER: '${POSTGRES_USER:?err}',
        POSTGRES_PASSWORD: '${POSTGRES_PASS:?err}',
      },
      restart: 'always',
      networks: {
        default: { aliases: [alias] },
        [infra.net.netName('postgres')]: { aliases: [alias] },   // shared-postgres
        [infra.net.netName('dbBackups')]: { aliases: [alias] },  // shared-db-backups
      },
      healthcheck: {
        test: 'pg_isready -U ${POSTGRES_USER} -h localhost -d postgres',
        interval: '5s',
        timeout: '5s',
        retries: 10,
      },
    },

    pgadmin: {
      image: 'dpage/pgadmin4:' + pgadminVersion,
      profiles: ['full'],
      ports: ['5050:80'],
      environment: {
        PGADMIN_DEFAULT_EMAIL: 'briankenkel.t@gmail.com',
        // Secret — interpolated from /dev/shm/postgres.env (parent include.env_file)
        PGADMIN_DEFAULT_PASSWORD: '${PG_ADMIN_PASS:?err}',
        PGADMIN_CONFIG_SERVER_MODE: 'True',
        PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: 'True',
      },
      networks: { default: {} },
    },
  },

  networks:
    infra.net.default(stack)       // default net -> 'postgres' (private; db + pgadmin)
    + infra.net.own('postgres')     // shared-postgres (owned; apps join)
    + infra.net.join('dbBackups'),  // shared-db-backups (databasus owns)

  volumes: { db: {} },
}
