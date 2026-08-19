// Cloudflare Tunnel egress; apps are reached via their exposed ports.
// cloudflared.env supplies TUNNEL_TOKEN.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = '2026.5.2';

{
  name: refs.name,
  networks: { default: { name: refs.name } },

  services: {
    [refs.tunnel.key]: {
      container_name: refs.tunnel.ext,
      image: 'cloudflare/cloudflared:' + version,
      restart: lib.collections.restart.unlessStopped,
      command: 'tunnel --no-autoupdate run',
      environment: {
        TZ: 'America/New_York',
        TUNNEL_TOKEN: '${TUNNEL_TOKEN:?please provide a Tunnel Token}',
      },
    },
  },
}
