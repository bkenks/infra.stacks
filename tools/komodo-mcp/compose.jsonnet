{
  name: 'komodo-mcp',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/komodo-mcp.env'],
    },
  ],
}
