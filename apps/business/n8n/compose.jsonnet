{
  name: 'n8n',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/postgres.env'],
    },
  ],
}
