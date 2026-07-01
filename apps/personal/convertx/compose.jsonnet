// convertx — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/convertx.env (rendered by the Infisical agent;
// registry agentServices dest `convertx.env`).
{
  name: 'convertx',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/convertx.env'],
    },
  ],
}
