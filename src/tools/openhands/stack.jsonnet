// openhands: Agent Canvas, the OpenHands web UI for running coding agents (its own agent,
// or Claude Code / Codex over ACP) against the projects mounted at /projects.
local lib = import 'lib.libsonnet';

local refs = lib.Project {
  name:: 'openhands',

  app:: self.Service { role:: lib.collections.role.APP },

  // Settings, secrets and conversation history — the container's ~/.openhands.
  home:: self.Volume { key:: 'home' },
};

local version = '1.16.0';
local port = '8000';
local projectsDir = lib.collections.dirs.docker.bindMounts + '/' + refs.name + '/projects';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    volumes: refs.home.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/openhands'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/openhands/agent-canvas:' + version,
        restart: lib.collections.restart.onFailure(5),
        stdin_open: true,
        tty: true,
        depends_on: lib.secretsReady,
        // LOCAL_BACKEND_API_KEY (the API key the UI presents to the server) and
        // OH_SECRET_KEY (encrypts stored settings and secrets) arrive from
        // infisical-secrets, so they survive the container being recreated.
        environment: {
          TZ: 'America/Chicago',
        },
        expose: [port],
        ports: ['%s:18027:%s' % [lib.collections.ip.loopback, port]],
        volumes: [
          refs.home.mount('/home/openhands/.openhands'),
          projectsDir + ':/projects',
        ],
      },
    },
  },
}
