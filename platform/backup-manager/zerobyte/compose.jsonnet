// zerobyte — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_files for the child:
//   /dev/shm/platform.env              -> SECRET__APP_SECRET (Ansible, from vault)
//   /etc/ansible-managed/tailscale.env -> TAILSCALE_HOSTNAME (per-host, self-refreshing)
{
  name: 'zerobyte',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [
        '/dev/shm/platform.env',
        '/etc/ansible-managed/tailscale.env',
      ],
    },
  ],
}
