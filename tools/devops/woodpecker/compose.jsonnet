// woodpecker CI: `server` (UI/API+gRPC, joins shared-proxy) and `agent` (runs pipeline
// steps via host Docker socket, talks to server only over the stack's default net).
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'woodpecker';
local s = c.stack(stack);
local n = s.names;

local version = 'v3.15.0';
local httpPort = 8000;
local grpcPort = 9000;

local manifest = {
  name: stack,

  services: {
    server: {
      image: 'docker.io/woodpeckerci/woodpecker-server:' + version,
      container_name: n.container('server'),
      volumes: ['server' + ':/var/lib/woodpecker'],
      environment: {
        // Must match the OAuth2 app's redirect URI in Forgejo.
        WOODPECKER_HOST: 'https://peck.' + reg.domains.ktbinternal,
        // Any Forgejo user may log in.
        WOODPECKER_OPEN: 'true',
        // Uses Forgejo (not gitea) as the forge.
        WOODPECKER_FORGEJO: 'true',
        WOODPECKER_FORGEJO_URL: 'https://fj.' + reg.domains.ktbinternal,
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
      networks: {
        default: { aliases: [n.container('server')] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container('server')] },
      },
      labels: s.proxy.add('woodpecker', 'peck', httpPort),
    } + c.publish(18016, httpPort),

    agent: {
      image: 'docker.io/woodpeckerci/woodpecker-agent:' + version,
      container_name: n.container('agent'),
      command: 'agent',
      depends_on: ['server'],
      volumes: [
        'agent' + ':/etc/woodpecker',
        // Intentional: agent runs pipeline steps as sibling containers via the host daemon.
        '/var/run/docker.sock:/var/run/docker.sock',
      ],
      environment: {
        WOODPECKER_SERVER: 'server:' + std.toString(grpcPort),
        WOODPECKER_MAX_WORKFLOWS: std.toString(2),
        // Secret — must match server's WOODPECKER_AGENT_SECRET exactly.
        WOODPECKER_AGENT_SECRET: '${WOODPECKER_AGENT_SECRET:?err}',
      },
      restart: 'on-failure:5',
      networks: {
        default: { aliases: [n.container('agent')] },
      },
    },
  },

  volumes: {
    server: { name: n.volume('server') },
    agent: { name: n.volume('agent') },
  },

  networks:
    s.network.default
    + s.network.join(reg.sharedNetworks.proxy),
};

c.render(stack, manifest, [secrets.woodpecker.path])
