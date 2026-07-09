{
  name: 'stream',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/stream.env'],
    },
  ],
}
