local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = 'latest';
local hostPort = '18022';
local containerPort = '7777';

// The world lives under the tree file-browser-quantum serves, so it is reachable from the
// browser as well — hence the shared path out of the registry rather than a local literal.
local worldPath = lib.registry.dirs.fileBrowser.shared + '/terraria/worlds/columbia_plaza';

{
  name: refs.name,
  networks: refs.networks,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'ghcr.io/beardedio/terraria:' + version,
      restart: lib.restart.unlessStopped,
      volumes: [worldPath + ':/config'],
      environment: { world: 'Columbia_Plaza.wld' },
      ports: ['%s:%s:%s' % [lib.ip.loopback, hostPort, containerPort]],
      tty: true,
      stdin_open: true,
    },
  },
}
