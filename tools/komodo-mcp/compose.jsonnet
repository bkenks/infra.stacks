// komodo-mcp — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/komodo-mcp.env (rendered by the Infisical
// agent; registry agentServices dest `komodo-mcp.env`).
{
  name: 'komodo-mcp',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/komodo-mcp.env'],
    },
  ],
}
