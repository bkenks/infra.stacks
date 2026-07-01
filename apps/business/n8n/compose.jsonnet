// n8n — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/postgres.env (rendered by the Infisical
// agent; registry agentServices dest `postgres.env`).
{
  name: 'n8n',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/postgres.env'],
    },
  ],
}
