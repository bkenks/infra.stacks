{
  name: 'paperless',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/paperless.env'],
    },
  ],
}
