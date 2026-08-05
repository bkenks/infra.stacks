// Cloudflare Tunnel egress; apps are reached via their exposed ports.
// env_file cloudflared.env supplies CLOUDFLARE_TUNNEL_TOKEN.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'cloudflared';
local version = '2026.5.2';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.TUNNEL]: lib.Service {
      image: 'cloudflare/cloudflared:' + version,
      command: 'tunnel --no-autoupdate run',
      environment: {
        TZ: 'America/New_York',
        TUNNEL_TOKEN: '${TUNNEL_TOKEN:?please provide a Tunnel Token}',
      },
    },
  }),
  [lib.SecretOrBootstrap('cloudflared')],
)
