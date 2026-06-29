// network-bootstrap — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Includes the rendered child compose.stack.yaml. No secrets, no env_file: this
// stack only creates the shared networks and exits.
{
  name: 'docker-resource-manager',
  include: [
    { path: './compose.stack.yaml' },
  ],
}
