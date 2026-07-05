// komodo — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: ${ANSIBLE_SECRETS_FILE:-/dev/shm/komodo_core.env} supplies
// the KOMODO_*/MONGO_* secrets (Ansible bootstrap uses platform.env; steady-state
// uses the agent-rendered komodo_core.env — named to avoid colliding with the
// committed ./core.env, which holds non-secret tunables). DOCKER_VOLUMES (per-host)
// comes from Komodo's stack Environment.
local lib = import 'lib.libsonnet';
local reg = lib.registry;

{
  name: 'komodo',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [reg.envFiles.platform('komodo_core.env')],
    },
  ],
}
