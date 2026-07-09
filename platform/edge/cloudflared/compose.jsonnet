// Joins shared-proxy so tunnel ingress can route to Traefik by name (e.g. `https://traefik:443`).
// env_file cloudflared.env supplies CLOUDFLARE_TUNNEL_TOKEN.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

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
        TUNNEL_TOKEN: '${CLOUDFLARE_TUNNEL_TOKEN:?err}',
      },
      restart: 'unless-stopped',
      networks: {
        [reg.sharedNetworks.proxy.name]: { aliases: [cf.extName] },
      },
    },
  },

  networks:
    s.network.default   // unused here — no peers
    + s.network.join('proxy'),  // owned by traefik
};

c.render(stack, manifest, [c.envPath.platform('cloudflared')])
