{
  name: 'openproject',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/openproject.env', '/dev/shm/postgres.env'],
    },
  ],
}
