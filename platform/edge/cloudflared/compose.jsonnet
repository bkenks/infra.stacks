// cloudflared — per-host Cloudflare Tunnel connector.
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Joins the host's shared-proxy network so tunnel ingress can route to Traefik
// by name (e.g. `https://traefik:443`). No private-net peers — single service.
//
// TUNNEL_TOKEN is a secret, interpolated from /dev/shm/node_cloudflared.env
// (rendered by the Infisical agent; declared as the interpolation source in the
// parent compose.yaml's include.env_file).
local infra = import 'infra.libsonnet';

local stack = 'cloudflared';
local n = infra.net.names(stack);

local version = '2026.5.2';  // from interpolation-envs/production.env

{
  name: stack,

  services: {
    cloudflared: {
      image: 'cloudflare/cloudflared:' + version,
      command: 'tunnel --no-autoupdate run',
      environment: {
        TZ: 'America/New_York',
        // Secret — interpolated from /dev/shm/node_cloudflared.env (parent include.env_file)
        TUNNEL_TOKEN: '${CLOUDFLARE_TUNNEL_TOKEN:?err}',
      },
      restart: 'unless-stopped',
      networks: {
        [infra.net.netName('proxy')]: { aliases: [stack] },
      },
    },
  },

  networks:
    infra.net.default(stack)   // private default net (unused here — no peers)
    + infra.net.join('proxy'),  // join shared-proxy (owned by traefik)
}
