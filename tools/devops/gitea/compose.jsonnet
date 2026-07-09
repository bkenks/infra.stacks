{
  name: 'gitea',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/gitea.env'],
    },
  ],
}
