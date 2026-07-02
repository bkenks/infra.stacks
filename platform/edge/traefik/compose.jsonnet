// traefik — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/platform.env supplies CF_DNS_API_TOKEN for the
// DNS-01 ACME challenge (Ansible-rendered from the vault).
local lib = import 'lib.libsonnet';
local reg = lib.registry;

{
  name: 'traefik',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [
        reg.envFiles.platform('traefik.env')
      ],
    },
  ],
}
