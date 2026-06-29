// cloudflared — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/platform.env supplies CLOUDFLARE_TUNNEL_TOKEN
// (Ansible-rendered from the vault).
{
  name: 'cloudflared',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/platform.env'],
    },
  ],
}
