// woodpecker CI: `server` (UI/API+gRPC, reached via exposed port) and `agent` (runs pipeline
// steps via host Docker socket, talks to server only over the stack's default net).
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'woodpecker';
local version = 'v3.15.0';
local httpPort = 8000;
local grpcPort = 9000;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.SERVER]: lib.Service {
      image: 'docker.io/woodpeckerci/woodpecker-server:' + version,
      volumes_:: { server: '/var/lib/woodpecker' },
      environment: {
        // Must match the OAuth2 app's redirect URI in Forgejo.
        WOODPECKER_HOST: 'https://peck.' + reg.domains.ktbcloud,
        // Any Forgejo user may log in.
        WOODPECKER_OPEN: 'true',
        // Uses Forgejo (not gitea) as the forge.
        WOODPECKER_FORGEJO: 'true',
        WOODPECKER_FORGEJO_URL: 'https://fj.' + reg.domains.ktbcloud,
        // Exact match INCLUDING tag — keep in lockstep with the tag pinned in each
        // pipeline's .woodpecker.yml.
        WOODPECKER_PLUGINS_PRIVILEGED: 'woodpeckerci/plugin-docker-buildx:6.1.0',
        // Secrets — interpolated from /dev/shm/woodpecker.env (parent include.env_file)
        WOODPECKER_FORGEJO_CLIENT: '${WOODPECKER_FORGEJO_CLIENT:?err}',
        WOODPECKER_FORGEJO_SECRET: '${WOODPECKER_FORGEJO_SECRET:?err}',
        // Shared server<->agent gRPC auth secret — must match agent's value below.
        WOODPECKER_AGENT_SECRET: '${WOODPECKER_AGENT_SECRET:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(httpPort), std.toString(grpcPort)],
      ports: ['%s:18016:%s' % [reg.ips.loopback, httpPort]],
    },

    [role.AGENT]: lib.Service {
      image: 'docker.io/woodpeckerci/woodpecker-agent:' + version,
      command: 'agent',
      depends_on: [role.SERVER],
      volumes_:: { agent: '/etc/woodpecker' },
      // Intentional: agent runs pipeline steps as sibling containers via the host daemon.
      mounts_:: ['/var/run/docker.sock:/var/run/docker.sock'],
      environment: {
        WOODPECKER_SERVER: role.SERVER + ':' + std.toString(grpcPort),
        WOODPECKER_MAX_WORKFLOWS: std.toString(2),
        // Secret — must match server's WOODPECKER_AGENT_SECRET exactly.
        WOODPECKER_AGENT_SECRET: '${WOODPECKER_AGENT_SECRET:?err}',
      },
      restart: 'on-failure:5',
    },
  }),
  [lib.Secret('woodpecker')],
)
