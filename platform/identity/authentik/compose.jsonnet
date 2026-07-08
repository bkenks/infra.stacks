{
  name: 'authentik',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/authentik.env'],
    },
  ],
}
