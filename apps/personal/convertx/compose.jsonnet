{
  name: 'convertx',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/convertx.env'],
    },
  ],
}
