// stirling-pdf — self-hosted PDF toolkit (stirling-pdf.<domains.ktbinternal>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable. No DB dependency.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'stirling-pdf';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

local version = '2.10.1';
local port = 8080;

local base = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/stirling-pdf';

{
  name: stack,

  services: {
    [app]: {
      image: 'stirlingtools/stirling-pdf:' + version,
      container_name: n.container(app),
      volumes: [
        base + '/configs:/configs',
        base + '/tessdata:/usr/share/tessdata',
        base + '/logs:/logs',
        base + '/pipeline:/pipeline',
      ],
      environment: {
        SECURITY_ENABLELOGIN: 'true',
        // UI language(s) offered in the language picker.
        LANGS: 'en_US',
        // To seed admin credentials instead of the admin/stirling default, set
        // SECURITY_INITIALLOGIN_USERNAME / SECURITY_INITIALLOGIN_PASSWORD (treat
        // the password as a secret -> Infisical -> ${VAR:?err} here).
      },
      restart: 'unless-stopped',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add(stack, stack, port),
    },
  },

  networks:
    s.network.default
    + s.network.join('proxy'),
}
