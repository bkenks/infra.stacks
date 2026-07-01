// forgejo — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/forgejo.env (rendered by the Infisical
// agent; registry agentServices dest `forgejo.env`).
{
  name: 'forgejo',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/forgejo.env'],
    },
  ],
}
