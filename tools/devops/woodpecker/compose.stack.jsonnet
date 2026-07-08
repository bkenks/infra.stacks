// woodpecker — self-hosted CI: `server` (UI/API + gRPC) and `agent` (runs
// pipeline steps as sibling containers via the host Docker socket).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Only `server` joins shared-proxy (traefik owns) to be reachable.
// `agent` only talks to `server` internally via gRPC on the
// stack's own default net, so it doesn't join shared-proxy.
local lib = import 'lib.libsonnet';

local stack = 'woodpecker';
local n = lib.compose.names(stack);

local version = 'v3.15.0';
local httpPort = 8000;
local grpcPort = 9000;

{
  name: stack,

  services: {
    server: {
      image: 'docker.io/woodpeckerci/woodpecker-server:' + version,
      container_name: n.container('server'),
      volumes: ['server' + ':/var/lib/woodpecker'],
      environment: {
        // Public address; must match the OAuth2 app's redirect URI in Forgejo
        WOODPECKER_HOST: 'https://peck.' + lib.registry.rootDomain,
        // Allow any Forgejo user to log in.
        WOODPECKER_OPEN: 'true',
        // Forge: self-hosted Forgejo (source-of-truth git forge).
        WOODPECKER_FORGEJO: 'true',
        WOODPECKER_FORGEJO_URL: 'https://fj.' + lib.registry.rootDomain,
        // Plugins allowed to run privileged (docker-buildx needs Docker-in-Docker
        // to build images). Match is exact INCLUDING the tag — keep in lockstep
        // with the plugin tag pinned in each pipeline's .woodpecker.yml.
        WOODPECKER_PLUGINS_PRIVILEGED: 'woodpeckerci/plugin-docker-buildx:6.1.0',
        // Secrets — interpolated from /dev/shm/woodpecker.env (parent include.env_file)
        WOODPECKER_FORGEJO_CLIENT: '${WOODPECKER_FORGEJO_CLIENT:?err}',
        WOODPECKER_FORGEJO_SECRET: '${WOODPECKER_FORGEJO_SECRET:?err}',
        // Shared server<->agent gRPC auth secret — must match agent's value below.
        WOODPECKER_AGENT_SECRET: '${WOODPECKER_AGENT_SECRET:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(httpPort), std.toString(grpcPort)],
      networks: {
        default: { aliases: [n.alias('server')] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias('server')] },
      },
      labels: lib.mixins.proxyAdd('woodpecker', 'peck', httpPort),
    },

    agent: {
      image: 'docker.io/woodpeckerci/woodpecker-agent:' + version,
      container_name: n.container('agent'),
      command: 'agent',
      depends_on: ['server'],
      volumes: [
        'agent' + ':/etc/woodpecker',
        // Intentional privileged access: the agent runs pipeline steps as
        // sibling containers via the host daemon. Keep as-is.
        '/var/run/docker.sock:/var/run/docker.sock',
      ],
      environment: {
        // gRPC endpoint of the server (service name `server`, gRPC port 9000).
        WOODPECKER_SERVER: 'server:' + std.toString(grpcPort),
        WOODPECKER_MAX_WORKFLOWS: std.toString(2),
        // Secret — must match server's WOODPECKER_AGENT_SECRET exactly.
        WOODPECKER_AGENT_SECRET: '${WOODPECKER_AGENT_SECRET:?err}',
      },
      restart: 'on-failure:5',
      networks: {
        default: { aliases: [n.alias('agent')] },
      },
    },
  },

  volumes: {
    server: { name: n.volume('server') },
    agent: { name: n.volume('agent') },
  },

  networks:
    n.network
    + lib.compose.join('proxy'),
}
