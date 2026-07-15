// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
//
// authentik — identity provider / OIDC-SSO. Runs on rick (public VPS), served at
// authentik.ktbcloud.com. As of authentik 2025.10 Redis is gone (state moved to
// Postgres), so the stack is just server + worker + a dedicated Postgres.
//
// Postgres is bundled (NOT the shared cluster): the shared Postgres lives on
// littlebuddy, and a public-facing IdP shouldn't depend on the home LAN being
// reachable. Keeping the DB local to the VPS makes authentik self-contained.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'authentik';
local s = c.stack(stack);
local n = s.names;

local app = reg.roles.app;      // 'app'  — the server (user-facing) container
local worker = 'worker';        // background worker; same image, command: worker
local db = reg.roles.db;        // 'db'   — dedicated Postgres

local version = '2026.5.4';
local dbVersion = '16-alpine';

local httpPort = 9000;          // authentik server HTTP (Traefik/Pangolin terminates TLS)
local dbUser = stack;
local dbName = stack;

// Identical env on server AND worker — they must agree on DB + secret key.
local authentikEnv = {
  AUTHENTIK_POSTGRESQL__HOST: n.container(db),
  AUTHENTIK_POSTGRESQL__NAME: dbName,
  AUTHENTIK_POSTGRESQL__USER: dbUser,
  AUTHENTIK_POSTGRESQL__PASSWORD: '${AUTHENTIK_PG_PASS:?err}',
  AUTHENTIK_SECRET_KEY: '${AUTHENTIK_SECRET_KEY:?err}',
};

local manifest = {
  name: stack,

  services: {
    // ── Server: the web UI + API + OIDC endpoints ─────────────────────────────
    [app]: {
      image: 'ghcr.io/goauthentik/server:' + version,
      container_name: n.container(app),
      command: 'server',
      depends_on: {
        [db]: { condition: 'service_healthy' },
      },
      environment: authentikEnv,
      volumes: [n.volume('data') + ':/data'],
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.container(app)] },
      },
      expose: [std.toString(httpPort)],
    } + c.publish(18006, httpPort),  // 127.0.0.1:18006 → route authentik.ktbcloud.com here

    // ── Worker: background tasks, outpost mgmt, cert/blueprint processing ──────
    [worker]: {
      image: 'ghcr.io/goauthentik/server:' + version,
      container_name: n.container(worker),
      command: 'worker',
      // root + docker.sock: lets the worker manage the embedded/managed outposts.
      user: 'root',
      depends_on: {
        [db]: { condition: 'service_healthy' },
      },
      environment: authentikEnv,
      volumes: [
        '/var/run/docker.sock:/var/run/docker.sock',
        n.volume('data') + ':/data',
      ],
      restart: 'unless-stopped',
      networks: {
        default: { aliases: [n.container(worker)] },
      },
    },

    // ── DB: dedicated Postgres (see header for why not the shared cluster) ─────
    [db]: {
      image: 'docker.io/library/postgres:' + dbVersion,
      container_name: n.container(db),
      volumes: [n.volume(db) + ':/var/lib/postgresql/data'],
      environment: {
        POSTGRES_USER: dbUser,
        POSTGRES_DB: dbName,
        POSTGRES_PASSWORD: '${AUTHENTIK_PG_PASS:?err}',
      },
      restart: 'unless-stopped',
      healthcheck: {
        test: ['CMD-SHELL', 'pg_isready -d ' + dbName + ' -U ' + dbUser],
        interval: '30s',
        timeout: '5s',
        retries: 5,
        start_period: '20s',
      },
      networks: { default: { aliases: [n.container(db)] } },
      expose: ['5432'],
    },
  },

  volumes: {
    [n.volume('data')]: { name: n.volume('data') },
    [n.volume(db)]: { name: n.volume(db) },
  },

  networks:
    s.network.default,
};

c.render(stack, manifest, [secrets.authentik.path])
