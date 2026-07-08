// No interpolation env_file: config is committed ./periphery.env (service-level);
// DOCKER_VOLUMES comes from Komodo's stack Environment.
{
  name: 'komodo-periphery',
  include: [
    { path: './compose.stack.yaml' },
  ],
}
