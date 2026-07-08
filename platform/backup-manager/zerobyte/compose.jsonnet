// env_files: ANSIBLE_SECRETS_FILE (default /dev/shm/zerobyte.env) -> SECRET__APP_SECRET;
// tailscale.env -> TAILSCALE_HOSTNAME (per-host, self-refreshing).
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

{
  name: 'zerobyte',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [
        c.envPath.platform('zerobyte.env'),
        reg.envFiles.tailscale,
      ],
    },
  ],
}
