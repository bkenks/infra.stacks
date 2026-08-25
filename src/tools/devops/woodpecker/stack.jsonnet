// woodpecker CI: `server` (UI/API + gRPC, reached via its exposed port) and `agent` (runs
// pipeline steps via the host docker socket, talks to the server only over the private
// bridge).
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'woodpecker',

  server:: self.Service { role:: lib.collections.role.SERVER },
  agent:: self.Service { role:: lib.collections.role.AGENT },

  serverData:: self.Volume { key:: 'server' },
  agentData:: self.Volume { key:: 'agent' },
};

local version = 'v3.15.0';
local httpPort = '8000';
local grpcPort = '9000';

// Pipeline steps are sibling containers on the host daemon, so a cap on the agent
// container does not reach them — they are limited by the WOODPECKER_BACKEND_DOCKER_LIMIT_*
// vars below, which the docker backend applies to every step container it creates.
//
// Worst case on the host is these numbers times maxWorkflows (steps within one workflow
// run sequentially): 8 GiB and 4 CPUs. Tune here, not at the use sites.
local maxWorkflows = 2;
local mib = 1024 * 1024;
local stepMemBytes = 4 * 1024 * mib;
// Docker reads MemorySwap as memory+swap combined; equal to the memory limit means the
// step cannot swap at all, which is what keeps a runaway build from thrashing the host.
local stepMemSwapBytes = stepMemBytes;
// Microseconds of CPU per the 100000us default period: 200000 == 2 cores' worth.
local stepCpuQuota = 200000;

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.serverData.declare + refs.agentData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('woodpecker'),

      [refs.server.key]: {
        container_name: refs.server.ext,
        image: 'docker.io/woodpeckerci/woodpecker-server:' + version,
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        volumes: [refs.serverData.mount('/var/lib/woodpecker')],
        // WOODPECKER_FORGEJO_CLIENT, WOODPECKER_FORGEJO_SECRET and the shared
        // server<->agent WOODPECKER_AGENT_SECRET all arrive from infisical-secrets. Both
        // services depend on the same bundle, so they cannot disagree on the last of those.
        environment: {
          // Must match the OAuth2 app's redirect URI in Forgejo.
          WOODPECKER_HOST: 'https://peck.' + lib.collections.domain.ktbcloud,
          // Any Forgejo user may log in.
          WOODPECKER_OPEN: 'true',
          // Uses Forgejo (not gitea) as the forge.
          WOODPECKER_FORGEJO: 'true',
          WOODPECKER_FORGEJO_URL: 'https://fj.' + lib.collections.domain.ktbcloud,
          // Exact match INCLUDING tag — keep in lockstep with the tag pinned in each
          // pipeline's .woodpecker.yml.
          WOODPECKER_PLUGINS_PRIVILEGED: 'woodpeckerci/plugin-docker-buildx:6.1.0',
        },
        mem_limit: '1g',
        expose: [httpPort, grpcPort],
        ports: ['%s:18016:%s' % [lib.collections.ip.loopback, httpPort]],
      },

      [refs.agent.key]: {
        container_name: refs.agent.ext,
        image: 'docker.io/woodpeckerci/woodpecker-agent:' + version,
        restart: lib.collections.restart.onFailure(5),
        command: 'agent',
        depends_on: lib.secretsReady {
          [refs.server.key]: { condition: lib.collections.condition.started },
        },
        volumes: [
          refs.agentData.mount('/etc/woodpecker'),
          // Intentional: the agent runs pipeline steps as sibling containers via the host
          // daemon, which is a write on the socket.
          lib.collections.mounts.dockerSockRW,
        ],
        environment: {
          WOODPECKER_SERVER: refs.server.key + ':' + grpcPort,
          WOODPECKER_MAX_WORKFLOWS: std.toString(maxWorkflows),
          // Per-step-container limits, applied by the docker backend to every container it
          // starts. Bytes for memory, microseconds-per-period for CPU; 0 (the default) is
          // unlimited, which is what let concurrent image builds take the host down.
          WOODPECKER_BACKEND_DOCKER_LIMIT_MEM: std.toString(stepMemBytes),
          WOODPECKER_BACKEND_DOCKER_LIMIT_MEM_SWAP: std.toString(stepMemSwapBytes),
          WOODPECKER_BACKEND_DOCKER_LIMIT_CPU_QUOTA: std.toString(stepCpuQuota),
        },
        // The agent only supervises; the work happens in the step containers above.
        mem_limit: '512m',
      },
    },
  },
}
