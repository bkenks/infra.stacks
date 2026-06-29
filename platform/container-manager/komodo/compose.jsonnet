// komodo — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/platform.env supplies the KOMODO_*/MONGO_*
// secrets (Ansible-rendered from the vault). DOCKER_VOLUMES (per-host) comes from
// Komodo's stack Environment; ./core.env (service-level) holds non-secret tunables.
{
  name: 'komodo',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/platform.env'],
    },
  ],
}
