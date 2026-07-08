// zerobyte — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_files for the child:
//   ${ANSIBLE_SECRETS_FILE:-/dev/shm/zerobyte.env} -> SECRET__APP_SECRET (Ansible
//     bootstrap uses platform.env; steady-state uses the agent-rendered zerobyte.env)
//   /src/docker/files/tailscale.env -> TAILSCALE_HOSTNAME (per-host, self-refreshing)
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
