// termix — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// No secrets: nothing is rendered to /dev/shm by the Infisical agent for this stack.
{
  name: 'termix',
  include: [
    { path: './compose.stack.yaml' },
  ],
}
