// zerobyte — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_files for the child:
//   /dev/shm/platform.env              -> SECRET__APP_SECRET (Ansible, from vault)
//   /src/docker/files/tailscale.env -> TAILSCALE_HOSTNAME (per-host, self-refreshing)
local lib = import 'lib.libsonnet';
local r = lib.registry;

{
  name: 'zerobyte',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [
        '/dev/shm/platform.env',
        r.envFiles.tailscale,
      ],
    },
  ],
}
