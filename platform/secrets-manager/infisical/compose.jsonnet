// infisical — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/platform.env supplies the INFISICAL_* secrets
// (Ansible-rendered from the vault; infisical reads its own secrets despite being
// the server — the chicken-and-egg is solved by Ansible bootstrapping platform.env).
{
  name: 'infisical',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/platform.env'],
    },
  ],
}
