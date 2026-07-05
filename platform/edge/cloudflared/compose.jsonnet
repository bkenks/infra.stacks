// cloudflared — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: ${ANSIBLE_SECRETS_FILE:-/dev/shm/cloudflared.env} supplies
// CLOUDFLARE_TUNNEL_TOKEN (Ansible bootstrap uses platform.env; steady-state uses
// the agent-rendered cloudflared.env).
local lib = import 'lib.libsonnet';
local reg = lib.registry;

{
  name: 'cloudflared',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [reg.envFiles.platform('cloudflared.env')],
    },
  ],
}
