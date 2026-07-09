{
  name: 'pangolin',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/pangolin.env', '/dev/shm/cloudflare__dns-api-token.env'],
    },
  ],
}
