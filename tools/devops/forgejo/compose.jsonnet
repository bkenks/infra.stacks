{
  name: 'forgejo',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/forgejo.env'],
    },
  ],
}
