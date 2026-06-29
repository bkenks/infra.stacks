// komodo-periphery — parent compose (Komodo deploy entrypoint). Renders to
// compose.yaml. No interpolation env_file: config is committed ./periphery.env
// (service-level) and DOCKER_VOLUMES comes from Komodo's stack Environment.
{
  name: 'komodo-periphery',
  include: [
    { path: './compose.stack.yaml' },
  ],
}
