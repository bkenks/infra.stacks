// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'docuseal';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;
local pgHost = reg.endpoints.postgres.host.host;  // 'host.docker.internal'
local pgPort = reg.endpoints.postgres.host.port;  // 6109

local version = '2.5.3';
local port = 3000;

local manifest = {
  name: stack,

  services: {
    [app]: {
      image: 'docuseal/docuseal:' + version,
      container_name: n.container(app),
      volumes: [n.volume(app) + ':/data/docuseal'],
      environment: {
        PORT: std.toString(port),
        // Also the SSL switch: forces HTTPS redirects + absolute signing-link URLs.
        FORCE_SSL: stack + '.' + reg.domains.ktbinternal,
        DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@' + pgHost + ':' + std.toString(pgPort) + '/docuseal',
        SECRET_KEY_BASE: '${DOCUSEAL_SECRET_KEY_BASE:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port)],
      extra_hosts: ['host.docker.internal:host-gateway'],
      networks: {
        default: { aliases: [n.container(app)] },
      },
    } + c.publish(18002, port),
  },

  volumes: { [n.volume(app)]: { name: n.volume(app) } },

  networks:
    s.network.default,
};

c.render(stack, manifest, [secrets.docuseal.path, secrets.postgres.path])
