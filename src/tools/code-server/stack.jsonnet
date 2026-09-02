// code-server: VS Code in the browser (coder/code-server) on its own — no Coder control
// plane, no workspaces. Edits the projects mounted at /home/coder/project.
local lib = import 'lib.libsonnet';

local refs = lib.Project {
  name:: 'code-server',

  app:: self.Service { role:: lib.collections.role.APP },
};

local version = '4.135.0';
local port = '8080';
local home = '/home/coder';
local dir = lib.collections.dirs.docker.bindMounts + '/' + refs.name;
local mounts = {
  // ~/.config — code-server's own config.yaml.
  config: { host: dir + '/config', container: home + '/.config' },
  // ~/.local — extensions, user settings and workspace state.
  data: { host: dir + '/local', container: home + '/.local' },
  projects: { host: dir + '/projects', container: home + '/project' },
};
local mountPaths = [mounts[key].container for key in std.objectFields(mounts)];

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/code-server'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'codercom/code-server:' + version,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady,
        // HASHED_PASSWORD (argon2, the web login) arrives from infisical-secrets.
        environment: {
          TZ: 'America/Chicago',
        },
        expose: [port],
        ports: ['%s:18028:%s' % [lib.collections.ip.loopback, port]],
        volumes: [mounts[key].host + ':' + mounts[key].container for key in std.objectFields(mounts)],
        // The image runs as uid 1000 and never as root, so it cannot take ownership of a
        // bind source docker creates on the host (root-owned). The hook runs first, as
        // root, in an entrypoint-less image, and hands the mount points to that uid.
        pre_start: [{
          image: 'busybox:1.37',
          user: '0:0',
          command: ['chown', '1000:1000'] + mountPaths,
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
