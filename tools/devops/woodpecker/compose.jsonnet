{
  name: 'woodpecker',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/woodpecker.env'],
    },
  ],
}
