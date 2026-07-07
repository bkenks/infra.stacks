// infisical-agent — renders each host's stack secrets to /dev/shm (tmpfs/RAM).
//
// Long-running on EVERY host. It authenticates to Infisical with this host's own
// machine identity, then renders the folders named in AGENT_SERVICES (see the
// templates/ fragments, generated from the registry) to its /dev/shm dest file — the
// very files other stacks
// interpolate from (declared as include.env_file in each stack's parent
// compose.yaml). It is therefore the BOOTSTRAP of secret delivery and cannot
// pull its own auth from /dev/shm (chicken-and-egg): the machine-identity
// credential comes from the host/deploy env, not from a rendered file.
//
// REACH TO INFISICAL — public, cross-host. A docker network can't span hosts and
// this agent runs on every host, so it dials the server over the PUBLIC URL
// (https://infisical.homektb.com via Traefik) and does NOT join shared-infisical.
// INFISICAL_ADDRESS keeps a per-host override escape hatch (e.g. the Infisical
// host could point it at the internal http://infisical-app:8080) but defaults to
// the public URL so one config works on every host. See entrypoint.sh.
//
// Renders to compose.yaml — do not edit the YAML. Identity (name, version) is
// baked here; only genuine per-HOST values stay as ${...} for compose interp.
local lib = import 'lib.libsonnet';

// Naming is merged into the 'infisical' project (matches komodo-periphery's
// merge into 'komodo') — this stack is Infisical's agent, not its own app.
local stack = 'infisical';
local n = lib.compose.names(stack);

local version = '0.43.89';  // docker.io/infisical/cli

{
  name: stack,

  services: {
    agent: {
      image: 'docker.io/infisical/cli:' + version,
      container_name: n.container('agent'),  // 'infisical_agent'
      entrypoint: ['/bin/sh', '/agent/entrypoint.sh'],
      volumes: [
        './files/entrypoint.sh:/agent/entrypoint.sh:ro',
        './templates:/agent/templates:ro',     // per-service config fragments, generated from registry.agentServices
        '/dev/shm:/dev/shm',                   // read creds + write rendered <stack>.env files
      ],
      environment: {
        AGENT_HOST: '${AGENT_HOST:?err}',          // per-host: drives ${AGENT_HOST} secret-path subs
        AGENT_SERVICES: '${AGENT_SERVICES:?err}',  // per-host: which templates/ fragments to render
        // per-ROLE: drives ${AGENT_ROLE} secret-path subs (e.g. /roles/${AGENT_ROLE}/newt).
        // Optional — only hosts opting into a role-scoped service need it set.
        AGENT_ROLE: '${AGENT_ROLE:-}',
        // Machine-identity auth — the bootstrap credential. From the deploy env
        // (the Komodo/node path); it can't come from a rendered /dev/shm file
        // (this agent produces those). entrypoint.sh also accepts pre-written
        // /dev/shm files as a fallback for the Ansible/control-plane path.
        INFISICAL_CLIENT_ID: '${INFISICAL_CLIENT_ID:?err}',
        INFISICAL_CLIENT_SECRET: '${INFISICAL_CLIENT_SECRET:?err}',
        // Public URL by default (works on every host); per-host override allowed.
        INFISICAL_ADDRESS: '${INFISICAL_ADDRESS:-' + lib.compose.publicUrl('infisical') + '}',
      },
      networks: {
        default: { aliases: [n.alias('agent')] },  // egress to reach the public Infisical URL
      },
      restart: 'unless-stopped',
      // The agent stays "running" even when a template/auth permanently fails, so
      // liveness never flips it. entrypoint.sh stamps /tmp/agent.last_err with the
      // epoch of every ERR/FTL/PNC line; flag unhealthy only while an error was
      // logged within the last 180s. A window (not a plain grep) because the agent
      // is SILENT on success — a still-broken agent re-logs within the window and
      // stays unhealthy; once errors stop the stamp ages out and it recovers on
      // its own, no restart. '$$' escapes '$' past compose interpolation so the
      // arithmetic runs in the container shell, not at compose-parse time.
      healthcheck: {
        test: ['CMD-SHELL', '[ ! -f /tmp/agent.last_err ] || [ $$(( $$(date +%s) - $$(cat /tmp/agent.last_err) )) -ge 180 ]'],
        interval: '30s',
        timeout: '5s',
        retries: 2,
        start_period: '30s',
      },
    },
  },

  networks: n.network,  // private net (renamed default) 'infisical' — shared name with infisical-core's own default net, same tradeoff as komodo-periphery/komodo
}
