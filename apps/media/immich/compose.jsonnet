// immich — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/immich.env (rendered by the Infisical agent;
// registry agentServices dest `immich.env`).
{
  name: 'immich',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/immich.env'],
    },
  ],
}
