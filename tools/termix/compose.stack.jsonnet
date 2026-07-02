// termix — self-hosted web SSH/terminal + server-management UI, with guacd
// (Apache Guacamole proxy daemon) as an internal-only sidecar for remote-desktop
// connections. Renders to compose.stack.yaml — do not edit the YAML.
//
// Joins shared-proxy (traefik owns) so `app` is reachable; guacd is internal
// only, reached by `app` over this stack's own default network.
local lib = import 'lib.libsonnet';

local stack = 'termix';
local n = lib.compose.names(stack);
local app = lib.registry.roles.app;
local guacd = 'guacd';

local appVersion = '2.4.1';    // ghcr.io/lukegus/termix
local guacdVersion = '1.6.0';  // docker.io/guacamole/guacd
local port = 8080;
local guacdPort = 4822;

{
  name: stack,

  services: {
    [app]: {
      image: 'ghcr.io/lukegus/termix:' + appVersion,
      container_name: n.container(app),
      depends_on: { [guacd]: { condition: 'service_started' } },
      volumes: [app + ':/app/data'],
      environment: { PORT: std.toString(port) },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD', 'wget', '-q', '--spider', 'http://localhost:' + std.toString(port) + '/'],
        interval: '15s',
        timeout: '5s',
        retries: 10,
      },
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.alias(app)] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias(app)] },
      },
      labels: lib.mixins.proxyAdd(stack, stack, port),
    },

    [guacd]: {
      image: 'docker.io/guacamole/guacd:' + guacdVersion,
      container_name: n.container(guacd),
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD-SHELL', 'nc -z localhost ' + std.toString(guacdPort) + ' || exit 1'],
        interval: '15s',
        timeout: '5s',
        retries: 10,
      },
      expose: [std.toString(guacdPort)],
      networks: { default: { aliases: [n.alias(guacd)] } },
    },
  },

  volumes: { [app]: { name: n.volume(app) } },

  networks: n.network + lib.compose.join('proxy'),
}
