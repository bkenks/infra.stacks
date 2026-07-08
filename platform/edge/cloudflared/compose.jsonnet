// cloudflared — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: ${ANSIBLE_SECRETS_FILE:-/dev/shm/cloudflared.env} supplies
// CLOUDFLARE_TUNNEL_TOKEN (Ansible bootstrap uses platform.env; steady-state uses
// the agent-rendered cloudflared.env).
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
