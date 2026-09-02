// code-server: VS Code in the browser (coder/code-server) on its own — no Coder control
// plane, no workspaces. Edits the projects mounted at /home/coder/project.
local lib = import 'lib.libsonnet';

local refs = lib.Project {
  name:: 'code-server',

  app:: self.Service { role:: lib.collections.role.APP },

  // ~/.config — code-server's own config.yaml.
  dotConfig:: self.Volume { key:: 'config' },
  // ~/.local — extensions, user settings and workspace state.
  dotLocal:: self.Volume { key:: 'local' },
};

local version = '4.135.0';
local port = '8080';
local uid = '1000';
local gid = '1000';
local home = '/home/coder';
local projectsDir = lib.collections.dirs.docker.bindMounts + '/' + refs.name + '/projects';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    volumes: refs.dotConfig.declare + refs.dotLocal.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/code-server'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'codercom/code-server:' + version,
        restart: lib.collections.restart.unlessStopped,
        user: uid + ':' + gid,
        depends_on: lib.secretsReady,
        // HASHED_PASSWORD (argon2, the web login) arrives from infisical-secrets.
        environment: {
          DOCKER_USER: 'coder',
          TZ: 'America/Chicago',
        },
        expose: [port],
        ports: ['%s:18028:%s' % [lib.collections.ip.loopback, port]],
        volumes: [
          refs.dotConfig.mount(home + '/.config'),
          refs.dotLocal.mount(home + '/.local'),
          projectsDir + ':' + home + '/project',
        ],
        // The service runs unprivileged, but a fresh named volume and a bind source docker
        // creates on the host both arrive root-owned. The hook runs first, as root, in an
        // entrypoint-less image, and hands the mount points to the service user.
        pre_start: [{
          image: 'busybox:1.37',
          user: '0:0',
          command: [
            'chown',
            uid + ':' + gid,
            home + '/.config',
            home + '/.local',
            home + '/project',
          ],
        }],
        healthcheck: {
          test: ['CMD', 'curl', '-fsS', '--max-time', '2', 'http://localhost:%s/healthz' % port],
          interval: '30s',
          timeout: '10s',
          retries: 5,
        },
      },
    },
  },
}
