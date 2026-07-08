// docuseal — self-hosted document signing (docuseal.<domains.ktbinternal>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable and shared-postgres
// (postgres owns) to reach its DB.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'docuseal';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;
local pgHost = reg.endpoints.postgres.container.host;  // 'postgres-db'
local pgPort = reg.endpoints.postgres.container.port;  // 5432

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
        FORCE_SSL: stack + '.' + reg.domains.ktbinternal,
        // Secrets — interpolated from /dev/shm/docuseal.env + /dev/shm/postgres.env
        // (parent include.env_file)
        DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + std.toString(pgPort) + '/docuseal',
        SECRET_KEY_BASE: '${DOCUSEAL_SECRET_KEY_BASE:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
        [reg.sharedNetworks.postgres.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add(stack, stack, port),
    },
  },

  volumes: { [n.volume(app)]: { name: n.volume(app) } },

  networks:
    s.network.default
    + s.network.join('proxy')
    + s.network.join('postgres'),
}
