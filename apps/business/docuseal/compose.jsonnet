// docuseal — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/docuseal.env + /dev/shm/postgres.env (rendered
// by the Infisical agent; registry agentServices dest `docuseal.env`/`postgres.env`).
{
  name: 'docuseal',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/docuseal.env', '/dev/shm/postgres.env'],
    },
  ],
}
