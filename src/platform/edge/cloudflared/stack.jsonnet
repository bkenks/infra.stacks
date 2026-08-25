// Cloudflare Tunnel egress; apps are reached via their exposed ports.
// cloudflared.env supplies TUNNEL_TOKEN.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'cloudflared',
  // Brought up by the control plane before the agent exists to render anything.
  envFiles:: [lib.SecretOrBootstrap('cloudflared')],

  tunnel:: self.Service { role:: lib.collections.role.TUNNEL },
};

local version = '2026.5.2';

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
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
  },
}
