// woodpecker — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/woodpecker.env (rendered by the Infisical
// agent; registry agentServices dest `woodpecker.env`).
{
  name: 'woodpecker',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/woodpecker.env'],
    },
  ],
}
