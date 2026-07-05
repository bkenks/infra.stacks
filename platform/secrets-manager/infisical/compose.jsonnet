// infisical — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: ${ANSIBLE_SECRETS_FILE:-/dev/shm/infisical.env} supplies
// the INFISICAL_* secrets. Ansible bootstraps them once (platform.env, from the
// vault, for the initial cold start before Infisical or its agent exist); from
// then on the infisical-agent re-renders infisical.env from the matching
// registry.agentServices folder, same as every other platform stack — this
// covers tmpfs entries getting evicted without a full host reboot, so a manual
// Ansible re-run isn't the only way to recover.
local lib = import 'lib.libsonnet';
local reg = lib.registry;

{
  name: 'infisical',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [reg.envFiles.platform('infisical.env')],
    },
  ],
}
