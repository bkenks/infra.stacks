// openproject — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/openproject.env + /dev/shm/postgres.env (rendered
// by the Infisical agent; registry agentServices dest `openproject.env`/`postgres.env`).
{
  name: 'openproject',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/openproject.env', '/dev/shm/postgres.env'],
    },
  ],
}
