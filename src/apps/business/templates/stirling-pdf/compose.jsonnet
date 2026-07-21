// Compiles to compose.yaml and compose.stack.yaml — do not edit the YAML.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'stirling-pdf';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

local version = '2.10.1';
local port = 8080;

local base = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/apps/stirling-pdf';

local manifest = {
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
        LANGS: 'en_US',
        // Default login is admin/stirling. To change it, set
        // SECURITY_INITIALLOGIN_USERNAME / SECURITY_INITIALLOGIN_PASSWORD.
      },
      restart: 'unless-stopped',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.container(app)] },
      },
    } + c.publish(18012, port),
  },

  networks:
    s.network.default,
};

c.render(stack, manifest)
