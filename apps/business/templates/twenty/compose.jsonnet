{
  name: 'twenty',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/twenty.env', '/dev/shm/postgres.env'],
    },
  ],
}
