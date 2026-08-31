// authentik — identity provider / OIDC-SSO. Runs on rick (public VPS), served at
// registry.endpoint.serviceGroup.authentik.proxy.url. As of authentik 2025.10 Redis is gone (state
// moved to Postgres), so the stack is server + worker + a dedicated Postgres.
//
// Postgres is bundled (NOT the shared cluster): the shared cluster lives on littlebuddy,
// and a public-facing IdP should not depend on the home LAN being reachable.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'authentik',

  app:: self.Service { role:: lib.collections.role.APP },
  worker:: self.Service { role:: lib.collections.role.WORKER },
  db:: self.Service { role:: lib.collections.role.DB },

  // Shared by app and worker; declared once, mounted twice.
  data:: self.Volume { key:: 'data' },
  dbData:: self.Volume { key:: 'db' },
};

local version = '2026.5.4';
local dbVersion = '16-alpine';
// authentik server HTTP; Traefik/Pangolin terminates TLS in front of it.
local httpPort = '9000';
local dbUser = refs.name;
local dbName = refs.name;
local gateway = lib.registry.network.shared.tailscale_gw_001;

// Identical on server AND worker — they must agree on the DB and the secret key.
// AUTHENTIK_POSTGRESQL__PASSWORD and AUTHENTIK_SECRET_KEY arrive from infisical-secrets;
// `db` reads the same password as POSTGRES_PASSWORD, so the bundle carries it under both
// names.
local authentikEnv = {
  AUTHENTIK_POSTGRESQL__HOST: refs.db.key,
  AUTHENTIK_POSTGRESQL__NAME: dbName,
  AUTHENTIK_POSTGRESQL__USER: dbUser,
};

local dbHealthy = lib.secretsReady {
  [refs.db.key]: { condition: lib.collections.condition.healthy },
};

{
  compose: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [gateway.name]: { name: gateway.name, external: true },
    },
    volumes: refs.data.declare + refs.dbData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/authentik'),

      // ── Server: the web UI + API + OIDC endpoints ──────────────────────────────
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/goauthentik/server:' + version,
        restart: lib.collections.restart.unlessStopped,
        command: 'server',
        depends_on: dbHealthy,
        environment: authentikEnv,
        volumes: [refs.data.mount('/data')],
        expose: [httpPort],
        // 127.0.0.1:18006 — route authentik.ktbcloud.com here.
        ports: ['%s:18006:%s' % [lib.collections.ip.loopback, httpPort]],
      },

      // ── Worker: background tasks, outpost mgmt, cert/blueprint processing ───────
      [refs.worker.key]: {
        container_name: refs.worker.ext,
        image: 'ghcr.io/goauthentik/server:' + version,
        restart: lib.collections.restart.unlessStopped,
        command: 'worker',
        // root + docker.sock: lets the worker manage the embedded/managed outposts.
        user: 'root',
        depends_on: dbHealthy,
        environment: authentikEnv,
        volumes: [
          refs.data.mount('/data'),
          lib.collections.mounts.dockerSockRW,
        ],
      },

      // ── DB: dedicated Postgres (see the header for why not the shared cluster) ──
      [refs.db.key]: {
        container_name: refs.db.ext,
        image: 'docker.io/library/postgres:' + dbVersion,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady,
        networks: ['default', gateway.name],
        volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
        // POSTGRES_PASSWORD arrives from infisical-secrets.
        environment: {
          POSTGRES_USER: dbUser,
          POSTGRES_DB: dbName,
        },
        healthcheck: {
          test: ['CMD-SHELL', 'pg_isready -d %s -U %s' % [dbName, dbUser]],
          interval: '30s',
          timeout: '5s',
          retries: 5,
          start_period: '20s',
        },
        expose: ['5432'],
        ports: ['%s:18040:5432' % lib.collections.ip.loopback],
      },
    },
  },
}
