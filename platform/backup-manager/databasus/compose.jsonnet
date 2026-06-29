// databasus — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Includes the rendered child compose.stack.yaml. No interpolation env_file:
// databasus's only secret is the raw key file bind-mounted from /dev/shm.
{
  name: 'databasus',
  include: [
    { path: './compose.stack.yaml' },
  ],
}
