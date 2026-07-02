// docuseal — self-hosted document signing (docuseal.<rootDomain>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable and shared-postgres
// (postgres owns) to reach its DB.
local lib = import 'lib.libsonnet';

local stack = 'docuseal';
local n = lib.compose.names(stack);
local app = lib.registry.roles.app;
local pgHost = lib.registry.endpoints.postgres.private.host;  // 'postgres_db'
local pgPort = lib.registry.endpoints.postgres.private.port;  // 5432

local version = '2.5.3';
local port = 3000;

{
  name: stack,

  services: {
    [app]: {
      image: 'docuseal/docuseal:' + version,
      container_name: n.container(app),
      volumes: [n.volume(app) + ':/data/docuseal'],
      environment: {
        PORT: std.toString(port),
        // Canonical host. Doubles as the SSL switch (forces HTTPS redirects) and
        // the host DocuSeal uses to build absolute signing-link URLs in emails.
        // Traefik terminates TLS and forwards X-Forwarded-Proto.
        FORCE_SSL: stack + '.' + lib.registry.rootDomain,
        // Secrets — interpolated from /dev/shm/docuseal.env + /dev/shm/postgres.env
        // (parent include.env_file)
        DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + std.toString(pgPort) + '/docuseal',
        SECRET_KEY_BASE: '${DOCUSEAL_SECRET_KEY_BASE:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.alias(app)] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias(app)] },
        [lib.registry.sharedNetworks.postgres.name]: { aliases: [n.alias(app)] },
      },
      labels: lib.mixins.proxyAdd(stack, stack, port),
    },
  },

  volumes: { [n.volume(app)]: { name: n.volume(app) } },

  networks:
    n.network
    + lib.compose.join('proxy')
    + lib.compose.join('postgres'),
}
