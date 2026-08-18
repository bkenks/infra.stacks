// authentik — identity provider / OIDC-SSO. Runs on rick (public VPS), served at
// registry.endpoint.authentik.public.url. As of authentik 2025.10 Redis is gone (state
// moved to Postgres), so the stack is server + worker + a dedicated Postgres.
//
// Postgres is bundled (NOT the shared cluster): the shared cluster lives on littlebuddy,
// and a public-facing IdP should not depend on the home LAN being reachable.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = '2026.5.4';
local dbVersion = '16-alpine';
// authentik server HTTP; Traefik/Pangolin terminates TLS in front of it.
local httpPort = '9000';
local dbUser = refs.name;
local dbName = refs.name;
local gateway = lib.registry.networks.shared.tsGateway;

// Identical on server AND worker — they must agree on the DB and the secret key.
local authentikEnv = {
  AUTHENTIK_POSTGRESQL__HOST: refs.db.key,
  AUTHENTIK_POSTGRESQL__NAME: dbName,
  AUTHENTIK_POSTGRESQL__USER: dbUser,
  AUTHENTIK_POSTGRESQL__PASSWORD: '${AUTHENTIK_PG_PASS:?err}',
  AUTHENTIK_SECRET_KEY: '${AUTHENTIK_SECRET_KEY:?err}',
};

local dbHealthy = { [refs.db.key]: { condition: lib.condition.healthy } };

{
  name: refs.name,
  networks: refs.networks + gateway.attach,
  volumes: refs.data.declare + refs.dbData.declare,

  services: {
    // ── Server: the web UI + API + OIDC endpoints ──────────────────────────────
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'ghcr.io/goauthentik/server:' + version,
      restart: lib.restart.unlessStopped,
      command: 'server',
      depends_on: dbHealthy,
      environment: authentikEnv,
      volumes: [refs.data.mount('/data')],
      expose: [httpPort],
      // 127.0.0.1:18006 — route authentik.ktbcloud.com here.
      ports: ['%s:18006:%s' % [lib.ip.loopback, httpPort]],
    },

    // ── Worker: background tasks, outpost mgmt, cert/blueprint processing ───────
    [refs.worker.key]: {
      container_name: refs.worker.container,
      image: 'ghcr.io/goauthentik/server:' + version,
      restart: lib.restart.unlessStopped,
      command: 'worker',
      // root + docker.sock: lets the worker manage the embedded/managed outposts.
      user: 'root',
      depends_on: dbHealthy,
      environment: authentikEnv,
      volumes: [
        refs.data.mount('/data'),
        lib.mounts.dockerSockRW,
      ],
    },

    // ── DB: dedicated Postgres (see the header for why not the shared cluster) ──
    [refs.db.key]: {
      container_name: refs.db.container,
      image: 'docker.io/library/postgres:' + dbVersion,
      restart: lib.restart.unlessStopped,
      networks: ['default', gateway.name],
      volumes: [refs.dbData.mount('/var/lib/postgresql/data')],
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        POSTGRES_PASSWORD: '${AUTHENTIK_PG_PASS:?err}',
      },
      healthcheck: {
        test: ['CMD-SHELL', 'pg_isready -d %s -U %s' % [dbName, dbUser]],
        interval: '30s',
        timeout: '5s',
        retries: 5,
        start_period: '20s',
      },
      expose: ['5432'],
      ports: ['%s:18040:5432' % lib.ip.loopback],
    },
  },
}
