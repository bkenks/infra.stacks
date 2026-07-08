// env_file cloudflared.env supplies CLOUDFLARE_TUNNEL_TOKEN.
local c = import 'compose.libsonnet';

{
  name: 'cloudflared',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [c.envPath.platform('cloudflared.env')],
    },
  ],
}
