// No env_file: databasus's only secret is a raw key file bind-mounted from /dev/shm, not an env var.
{
  name: 'databasus',
  include: [
    { path: './compose.stack.yaml' },
  ],
}
