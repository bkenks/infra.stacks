// replaceme — single-service scaffold. Renders to compose.stack.yaml.
//
// Copy .template/ to the new stack's directory, then: rename `stack`, set
// `image`/`version`/`port`, and delete whichever of the blocks below this
// stack doesn't need (postgres join + DATABASE_URL, the secret env var,
// proxy join + labels). Worked examples elsewhere in this repo:
//   apps/business/docuseal              — simple, single-service, w/ shared-postgres
//   apps/personal/paperless (or apps/business/openproject) — multi-service
local lib = import 'lib.libsonnet';

local stack = 'replaceme';
local n = lib.compose.names(stack);
local app = lib.compose.roles.app;

// Only needed if this stack has its own DB on shared-postgres — delete these
// two locals (and the postgres network join + DATABASE_URL below) otherwise.
local pgHost = lib.compose.endpoint('postgres').private.host;  // 'postgres-db'
local pgPort = lib.compose.endpoint('postgres').private.port;  // 5432

local version = '0.0.0';
local port = 8080;

{
  name: stack,

  services: {
    [app]: {
      image: 'REPLACE_ME/image:' + version,
      container_name: n.container(app),

      // Explicit named volume, declared under `volumes:` below — avoids
      // Docker's implicit <project>_<service> naming.
      volumes: [n.volume('data') + ':/data'],

      environment: {
        PORT: std.toString(port),
        // Secrets — interpolated from /dev/shm/<stack>.env, pulled in by the
        // parent compose.jsonnet's (commented-out by default) include.env_file.
        // Delete if this stack has no secrets.
        SOME_SECRET: '${SOME_VAR:?err}',
        // DB login (non-secret host/port; POSTGRES_USER/PASS are secrets from
        // the same /dev/shm env). Delete alongside the pgHost/pgPort locals
        // if this stack has no DB.
        DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + std.toString(pgPort) + '/' + stack,
      },

      restart: 'on-failure:5',
      expose: [std.toString(port)],

      networks: {
        default: { aliases: [n.alias(app)] },
        // Join shared-proxy (traefik owns) so this service is reachable.
        [lib.compose.netName('proxy')]: { aliases: [n.alias(app)] },
        // Join shared-postgres (postgres owns) to reach the DB — delete if unused.
        [lib.compose.netName('postgres')]: { aliases: [n.alias(app)] },
      },

      // Traefik routing + TLS on the shared wildcard cert. Delete if this
      // service isn't reached via the web.
      labels: lib.mixins.proxyAdd(stack, stack, port),
    },
  },

  volumes: { [n.volume('data')]: { name: n.volume('data') } },

  networks:
    n.network
    + lib.compose.join('proxy')
    + lib.compose.join('postgres'),
}
