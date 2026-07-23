// gitea: self-hosted git forge. SSH via raw-TCP Traefik router on :22.
// `db` is dedicated Postgres, NOT shared-postgres.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'gitea';
local appVersion = '1.24.4';   // docker.gitea.com/gitea
local dbVersion = '16-alpine'; // docker.io/library/postgres
local port = 3000;

local dbUser = 'gitea';
local dbName = 'gitea';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'docker.gitea.com/gitea:' + appVersion,
      depends_on: { [role.DB]: { condition: 'service_healthy' } },
      volumes_:: { app: '/data' },
      environment: {
        USER_UID: '1000',
        USER_GID: '1000',
        GITEA__database__DB_TYPE: 'postgres',
        GITEA__database__HOST: ref[role.DB] + ':5432',
        GITEA__database__NAME: dbName,
        GITEA__database__USER: dbUser,
        // Secret — interpolated from /dev/shm/gitea.env (parent include.env_file)
        GITEA__database__PASSWD: '${GITEA_DB_PASSWORD:?err}',
        // SSH: advertised (clone URL) port vs. what the container listens on.
        GITEA__SERVER__SSH_PORT: '2222',
        GITEA__SERVER__SSH_LISTEN_PORT: '22',
        GITEA__SERVER__SSH_DOMAIN: 'gitea.' + reg.domains.ktbinternal,

        // DISABLED by default: fresh installs auto-generate these in app.ini.
        // RESTORE ONLY: uncomment these + matching lines in infisical/files/agent-config.yaml,
        // using the ORIGINAL app.ini values — a mismatch breaks decryption of existing 2FA/creds.
        // GITEA__security__SECRET_KEY: '${GITEA_SECRET_KEY:?err}',
        // GITEA__security__INTERNAL_TOKEN: '${GITEA_INTERNAL_TOKEN:?err}',
        // GITEA__oauth2__JWT_SECRET: '${GITEA_JWT_SECRET:?err}',
      },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD', 'wget', '-q', '--spider', 'http://localhost:' + std.toString(port) + '/'],
        interval: '15s',
        timeout: '5s',
        retries: 10,
      },
      expose: [std.toString(port), '22'],
      ports: ['%s:18005:%s' % [reg.ips.loopback, port]],
    },

    [role.DB]: lib.Service {
      image: 'docker.io/library/postgres:' + dbVersion,
      volumes_:: { db: '/var/lib/postgresql/data' },
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        // Secret — interpolated from /dev/shm/gitea.env (parent include.env_file)
        POSTGRES_PASSWORD: '${GITEA_DB_PASSWORD:?err}',
      },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD-SHELL', 'pg_isready --username=' + dbUser],
        interval: '5s',
        timeout: '10s',
        retries: 10,
      },
      expose: ['5432'],
    },
  }),
  [lib.Secret('gitea')],
)
