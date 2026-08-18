// Serves the tree at registry.dir.fileBrowser — the paths live in the registry rather than
// here because terraria keeps its world under the same tree.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = 'stable';
local hostPort = '18450';
local appPort = '80';
local dir = lib.registry.dir.fileBrowser;

{
  name: refs.name,
  networks: { default: { name: refs.name } },

  services: {
    [refs.app.key]: {
      container_name: refs.app.ext,
      image: 'gtstef/filebrowser:' + version,
      restart: lib.restart.unlessStopped,
      volumes: [
        './files/config.yaml:/home/filebrowser/data/config.yaml:ro',
        dir.data + ':/data',
        dir.shared + ':/shared',
        dir.cache + ':/cache',
      ],
      expose: [appPort],
      ports: ['%s:%s:%s' % [lib.ip.loopback, hostPort, appPort]],
    },
  },
}
