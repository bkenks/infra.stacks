// Cloudflare Tunnel egress; apps are reached via their exposed ports.
// env_file cloudflared.env supplies CLOUDFLARE_TUNNEL_TOKEN.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'cloudflared';
local s = c.stack(stack);
local n = s.names;
local cf = {
  version: '2026.5.2',
  role: 'tunnel',
  extName: n.container(self.role),
};

local manifest = {
  name: stack,

  services: {
    [cf.role]: {
      image: 'cloudflare/cloudflared:' + cf.version,
      container_name: cf.extName,
      command: 'tunnel --no-autoupdate run',
      environment: {
        TZ: 'America/New_York',
        TUNNEL_TOKEN: '${TUNNEL_TOKEN:?please provide a Tunnel Token}',
      },
      restart: 'unless-stopped',
    },
  },

  networks: s.network.default,   // unused here — no peers
};

c.render(stack, manifest, [secrets.cloudflared.platformPath])
