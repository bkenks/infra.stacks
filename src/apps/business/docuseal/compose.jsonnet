// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'docuseal';
local version = '2.5.3';
local port = 3000;
local pg = reg.endpoint.postgres.container;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'docuseal/docuseal:' + version,
      volumes_:: { app: '/data/docuseal' },
      environment: {
        PORT: std.toString(port),
        // Also the SSL switch: forces HTTPS redirects + absolute signing-link URLs.
        FORCE_SSL: name + '.' + reg.domains.ktbcloud,
        DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@%s:%s/docuseal' % [pg.host, pg.port],
        SECRET_KEY_BASE: '${DOCUSEAL_SECRET_KEY_BASE:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port)],
      extra_hosts: ['host.docker.internal:host-gateway'],
      ports: ['%s:18002:%s' % [reg.ips.loopback, port]],
      networks_:: lib.network.join(reg.networks.shared.postgresDB),
    },
  },
  lib.network.attach(reg.networks.shared.postgresDB)
  ),
  [lib.Secret('docuseal'), lib.Secret('postgres')],
)
