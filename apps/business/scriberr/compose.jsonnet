// No secrets: nothing is rendered to /dev/shm for this stack.
{
  name: 'scriberr',
  include: [
    { path: './compose.stack.yaml' },
  ],
}
