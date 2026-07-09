{
  name: 'postgres',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/postgres.env'],
    },
  ],
}
