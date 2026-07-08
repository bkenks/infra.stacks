// stirling-pdf — self-hosted PDF toolkit (stirling-pdf.<domains.ktbinternal>).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable. No DB dependency.
local lib = import 'lib.libsonnet';

local stack = 'stirling-pdf';
local n = lib.compose.names(stack);
local app = lib.registry.roles.app;

local version = '2.10.1';
local port = 8080;

local base = lib.registry.dockerVolumes + '/apps/stirling-pdf';

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
        default: { aliases: [n.alias(app)] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias(app)] },
      },
      labels: lib.mixins.proxyAdd(stack, stack, port),
    },
  },

  networks:
    n.network
    + lib.compose.join('proxy'),
}
