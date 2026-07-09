{
  name: 'immich',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/immich.env'],
    },
  ],
}
