// cloudflared — per-host Cloudflare Tunnel connector.
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Joins the host's shared-proxy network so tunnel ingress can route to Traefik
// by name (e.g. `https://traefik:443`). No private-net peers — single service.
//
// TUNNEL_TOKEN is a secret, interpolated from /dev/shm/platform.env
// (rendered by Ansible for bootstrapped core platform services; declared as the
// interpolation source in the parent compose.yaml's include.env_file).
local lib = import 'lib.libsonnet';
local r = lib.registry;
local c = lib.compose;

local stack = 'cloudflare';
local n = c.names(stack);
local cf = {
  version: '2026.5.2',
  role: 'tunnel',
  extName: n.container(self.role),
};

{
  name: stack,

  services: {
    [cf.role]: {
      image: 'cloudflare/cloudflared:' + cf.version,
      container_name: cf.extName,
      command: 'tunnel --no-autoupdate run',
      environment: {
        TZ: 'America/New_York',
        // Secret — interpolated from /dev/shm/platform.env (parent include.env_file)
        TUNNEL_TOKEN: '${CLOUDFLARE_TUNNEL_TOKEN:?err}',
      },
      restart: 'unless-stopped',
      networks: {
        [r.sharedNetworks.proxy.name]: { aliases: [cf.extName] },
      },
    },
  },

  networks:
    n.network   // private default net (unused here — no peers)
    + lib.compose.join('proxy'),  // join shared-proxy (owned by traefik)
}
