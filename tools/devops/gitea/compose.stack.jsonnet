// gitea — self-hosted git forge. Reached via Traefik; SSH
// (git clone/push) via a raw-TCP Traefik router on port 22.
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable. `db` is this stack's
// OWN dedicated Postgres — it does NOT join shared-postgres.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'gitea';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;
local db = reg.roles.db;

local appVersion = '1.24.4';   // docker.gitea.com/gitea
local dbVersion = '16-alpine'; // docker.io/library/postgres
local port = 3000;

local dbUser = 'gitea';
local dbName = 'gitea';

{
  name: stack,

  services: {
    [app]: {
      image: 'docker.gitea.com/gitea:' + appVersion,
      container_name: n.container(app),
      depends_on: { [db]: { condition: 'service_healthy' } },
      volumes: [app + ':/data'],
      environment: {
        USER_UID: '1000',
        USER_GID: '1000',
        GITEA__database__DB_TYPE: 'postgres',
        GITEA__database__HOST: n.container(db) + ':5432',
        GITEA__database__NAME: dbName,
        GITEA__database__USER: dbUser,
        // Secret — interpolated from /dev/shm/gitea.env (parent include.env_file)
        GITEA__database__PASSWD: '${GITEA_DB_PASSWORD:?err}',
        // SSH: advertised (clone URL) port vs. what the container listens on.
        GITEA__SERVER__SSH_PORT: '2222',
        GITEA__SERVER__SSH_LISTEN_PORT: '22',
        GITEA__SERVER__SSH_DOMAIN: 'gitea.' + reg.domains.ktbinternal,

        // --- Security secrets — DISABLED by default ------------------------------
        // On a FRESH install Gitea auto-generates SECRET_KEY / INTERNAL_TOKEN /
        // JWT_SECRET and persists them in app.ini (in the gitea-data volume), so we
        // don't supply them. Leave these commented for normal deploys.
        //
        // RE-ENABLE ONLY WHEN RESTORING an existing gitea: uncomment these AND the
        // matching lines in infisical/files/agent-config.yaml, and store the
        // ORIGINAL values (the ones from the old app.ini) in Infisical under
        // /gitea. This pins the SECRET_KEY so previously-encrypted data (2FA,
        // stored mirror/login creds) stays decryptable. A mismatched value here
        // would BREAK that data — so only set values you know are correct.
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
      networks: {
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add(stack, stack, port) + {
        // --- SSH (raw TCP) --- proxyAdd only builds HTTP routers, so these are
        // added manually.
        'traefik.tcp.routers.gitea-ssh.rule': 'HostSNI(`*`)',
        'traefik.tcp.routers.gitea-ssh.entrypoints': 'gitea-ssh',
        'traefik.tcp.services.gitea-ssh.loadbalancer.server.port': '22',
      },
    },

    [db]: {
      image: 'docker.io/library/postgres:' + dbVersion,
      container_name: n.container(db),
      volumes: [db + ':/var/lib/postgresql/data'],
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
      networks: { default: { aliases: [n.container(db)] } },
      expose: ['5432'],
    },
  },

  volumes: {
    [app]: { name: n.volume(app) },
    [db]: { name: n.volume(db) },
  },

  networks:
    s.network.default
    + s.network.join('proxy'),
}
