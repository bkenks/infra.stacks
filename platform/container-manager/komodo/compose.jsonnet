// env_file komodo_core.env supplies KOMODO_*/MONGO_* secrets; named to avoid colliding with
// the committed ./core.env (non-secret tunables). DOCKER_VOLUMES comes from Komodo's stack Environment.
local c = import 'compose.libsonnet';

{
  name: 'komodo',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: [c.envPath.platform('komodo_core.env')],
    },
  ],
}
