// /dev/shm/platform.env supplies the machine-identity secrets INFISICAL_CLIENT_ID/SECRET.
// AGENT_HOST/AGENT_SERVICES/INFISICAL_ADDRESS are per-host, from Komodo's stack Environment.
//
// Naming is merged into the 'infisical' project (matches komodo-periphery's
// merge into 'komodo') — this stack is Infisical's agent, not its own app.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'infisical';
local s = c.stack(stack);
local n = s.names;

local version = '0.43.89';

local manifest = {
  name: stack,

  services: {
    agent: {
      image: 'docker.io/infisical/cli:' + version,
      container_name: n.container('agent'),
      entrypoint: ['/bin/sh', '/agent/entrypoint.sh'],
      volumes: [
        './files/entrypoint.sh:/agent/entrypoint.sh:ro',
        './templates:/agent/templates:ro',     // per-service config fragments, generated from registry
        '/dev/shm:/dev/shm',                   // read creds + write rendered <stack>.env files
      ],
      environment: {
        AGENT_HOST: '${AGENT_HOST:?err}',          // per-host: drives ${AGENT_HOST} secret-path subs
        AGENT_SERVICES: '${AGENT_SERVICES:?err}',  // per-host: which templates/ fragments to render
        // Bootstrap credential, from the deploy env — can't come from a rendered /dev/shm
        // file since this agent produces those. entrypoint.sh also accepts pre-written
        // /dev/shm files as a fallback for the Ansible/control-plane path.
        INFISICAL_CLIENT_ID: '${INFISICAL_CLIENT_ID:?err}',
        INFISICAL_CLIENT_SECRET: '${INFISICAL_CLIENT_SECRET:?err}',
        // Public URL by default (works on every host); per-host override allowed.
        INFISICAL_ADDRESS: '${INFISICAL_ADDRESS:-' + c.url(reg.endpoints.infisical).public + '}',
      },
      networks: {
        default: { aliases: [n.container('agent')] },  // egress to reach the public Infisical URL
      },
      extra_hosts: [ "host.docker.internal:host-gateway" ],
      restart: 'unless-stopped',
      // The agent stays "running" even when a template/auth permanently fails, so liveness
      // never flips it. entrypoint.sh stamps /tmp/agent.last_err with the epoch of every
      // ERR/FTL/PNC line; unhealthy only while an error logged within the last 180s — a
      // window, not a plain grep, because the agent is SILENT on success (a still-broken
      // agent keeps re-logging and stays unhealthy; once errors stop, it self-recovers).
      // '$$' escapes '$' past compose interpolation so the arithmetic runs in the container
      // shell, not at compose-parse time.
      healthcheck: {
        test: ['CMD-SHELL', '[ ! -f /tmp/agent.last_err ] || [ $$(( $$(date +%s) - $$(cat /tmp/agent.last_err) )) -ge 180 ]'],
        interval: '30s',
        timeout: '5s',
        retries: 2,
        start_period: '30s',
      },
    },
  },

  networks: s.network.default,  // shared name with infisical-core's own default net, same tradeoff as komodo-periphery/komodo
};

c.render('infisical-agent', manifest)
