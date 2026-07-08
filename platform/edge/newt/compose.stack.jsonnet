// newt — Pangolin "site" connector (fosrl/newt).
//
// Source of truth: this file compiles to compose.stack.yaml (do not edit the YAML).
// Registers this host as a Pangolin site (dials out to PANGOLIN_ENDPOINT) and
// forwards ingress to the host's Traefik. Joins the host's shared-proxy network
// so targets can address Traefik by name (e.g. `https://traefik:443`) — same
// shape as platform/edge/cloudflared, just a different upstream.
//
// NEWT_ID/NEWT_SECRET are secrets, interpolated from /dev/shm/newt.env (declared
// as the interpolation source in the parent compose.yaml's include.env_file).
// Host-scoped exactly like cloudflared: the agent renders them from the per-host
// Infisical folder /hosts/${AGENT_HOST}/newt — see registry agentServices.newt.
local lib = import 'lib.libsonnet';
local r = lib.registry;
local c = lib.compose;

local stack = 'newt';
local n = c.names(stack);
local nw = {
  version: '1.14.0',
  role: 'tunnel',
  extName: n.container(self.role),
};

{
  name: stack,

  services: {
    [nw.role]: {
      image: 'fosrl/newt:' + nw.version,
      container_name: nw.extName,
      environment: {
        TZ: 'America/New_York',
        // Non-secret control-plane endpoint (Pangolin server, this org).
        PANGOLIN_ENDPOINT: 'https://pangolin.' + r.rootDomain,
        // Secrets — interpolated from /dev/shm/newt.env (parent include.env_file),
        // rendered from Infisical infra project folder /roles/traefik-controller.
        NEWT_ID: '${NEWT_ID:?err}',
        NEWT_SECRET: '${NEWT_SECRET:?err}',
      },
      restart: 'unless-stopped',
      networks: {
        [r.sharedNetworks.proxy.name]: { aliases: [nw.extName] },
      },
      extra_hosts: ['host.docker.internal:host-gateway'],
    },
  },

  networks:
    n.network   // private default net (unused here — no peers)
    + lib.compose.join('proxy'),  // join shared-proxy (owned by traefik)
}
