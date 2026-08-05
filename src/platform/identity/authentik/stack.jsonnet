// Compiles to compose.yaml and stack.services.yaml — do not edit the YAML.
//
// authentik — identity provider / OIDC-SSO. Runs on rick (public VPS), served at
// authentik.ktbcloud.com. As of authentik 2025.10 Redis is gone (state moved to
// Postgres), so the stack is just server + worker + a dedicated Postgres.
//
// Postgres is bundled (NOT the shared cluster): the shared Postgres lives on
// littlebuddy, and a public-facing IdP shouldn't depend on the home LAN being
// reachable. Keeping the DB local to the VPS makes authentik self-contained.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'authentik';
local version = '2026.5.4';
local dbVersion = '16-alpine';

local httpPort = 9000;          // authentik server HTTP (Traefik/Pangolin terminates TLS)
local dbUser = name;
local dbName = name;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    // Identical env on server AND worker — they must agree on DB + secret key.
    local authentikEnv = {
      AUTHENTIK_POSTGRESQL__HOST: ref[role.DB],
      AUTHENTIK_POSTGRESQL__NAME: dbName,
      AUTHENTIK_POSTGRESQL__USER: dbUser,
      AUTHENTIK_POSTGRESQL__PASSWORD: '${AUTHENTIK_PG_PASS:?err}',
      AUTHENTIK_SECRET_KEY: '${AUTHENTIK_SECRET_KEY:?err}',
    },

    // ── Server: the web UI + API + OIDC endpoints ─────────────────────────────
    [role.APP]: lib.Service {
      image: 'ghcr.io/goauthentik/server:' + version,
      command: 'server',
      depends_on: { [role.DB]: { condition: 'service_healthy' } },
      environment: authentikEnv,
      volumes_:: { data: '/data' },
      expose: [std.toString(httpPort)],
      // 127.0.0.1:18006 → route authentik.ktbcloud.com here
      ports: ['%s:18006:%s' % [reg.ips.loopback, httpPort]],
    },

    // ── Worker: background tasks, outpost mgmt, cert/blueprint processing ──────
    [role.WORKER]: lib.Service {
      image: 'ghcr.io/goauthentik/server:' + version,
      command: 'worker',
      // root + docker.sock: lets the worker manage the embedded/managed outposts.
      user: 'root',
      depends_on: { [role.DB]: { condition: 'service_healthy' } },
      environment: authentikEnv,
      volumes_:: { data: '/data' },
      mounts_:: ['/var/run/docker.sock:/var/run/docker.sock'],
    },

    // ── DB: dedicated Postgres (see header for why not the shared cluster) ─────
    [role.DB]: lib.Service {
      image: 'docker.io/library/postgres:' + dbVersion,
      volumes_:: { db: '/var/lib/postgresql/data' },
      networks_:: lib.network.join(reg.networks.shared.tsGateway),
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        POSTGRES_PASSWORD: '${AUTHENTIK_PG_PASS:?err}',
      },
      healthcheck: {
        test: ['CMD-SHELL', 'pg_isready -d ' + dbName + ' -U ' + dbUser],
        interval: '30s',
        timeout: '5s',
        retries: 5,
        start_period: '20s',
      },
      expose: ['5432'],
      ports: [reg.ips.loopback + ":18040:5432"],
    },
  },
  lib.network.attach(reg.networks.shared.tsGateway)
  ),
  [lib.Secret('authentik')],
)
