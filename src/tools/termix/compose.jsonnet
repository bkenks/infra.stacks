// termix: web SSH/terminal + server-management UI; guacd (Guacamole proxy) is an internal-only
// sidecar for remote-desktop, reached by `app` over the stack's default net. No secrets for this stack.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'termix';
local guacd = 'guacd';         // app-specific sidecar, no shared role

local appVersion = '2.4.1';    // ghcr.io/lukegus/termix
local guacdVersion = '1.6.0';  // docker.io/guacamole/guacd
local port = 8080;
local guacdPort = 4822;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/lukegus/termix:' + appVersion,
      depends_on: { [guacd]: { condition: 'service_started' } },
      volumes_:: { app: '/app/data' },
      environment: { PORT: std.toString(port) },
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD', 'wget', '-q', '--spider', 'http://localhost:' + std.toString(port) + '/'],
        interval: '15s',
        timeout: '5s',
        retries: 10,
      },
      expose: [std.toString(port)],
      ports: ['%s:18014:%s' % [reg.ips.loopback, port]],
    },

    [guacd]: lib.Service {
      image: 'docker.io/guacamole/guacd:' + guacdVersion,
      restart: 'on-failure:5',
      healthcheck: {
        test: ['CMD-SHELL', 'nc -z localhost ' + std.toString(guacdPort) + ' || exit 1'],
        interval: '15s',
        timeout: '5s',
        retries: 10,
      },
      expose: [std.toString(guacdPort)],
    },
  }),
)
