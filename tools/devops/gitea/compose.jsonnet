// gitea — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/gitea.env (rendered by the Infisical agent;
// registry agentServices dest `gitea.env`).
{
  name: 'gitea',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/gitea.env'],
    },
  ],
}
