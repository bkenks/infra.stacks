// stream — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/stream.env (rendered by the Infisical agent;
// registry agentServices dest `stream.env`) — supplies SONARR_API_KEY /
// RADARR_API_KEY for configarr + decluttarr.
{
  name: 'stream',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/stream.env'],
    },
  ],
}
