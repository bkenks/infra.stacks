// twenty — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/twenty.env + /dev/shm/postgres.env (rendered
// by the Infisical agent; registry agentServices dest `twenty.env`/`postgres.env`).
{
  name: 'twenty',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/twenty.env', '/dev/shm/postgres.env'],
    },
  ],
}
