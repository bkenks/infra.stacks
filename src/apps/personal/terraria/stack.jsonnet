local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'terraria',

  app:: self.Service { role:: lib.collections.role.APP },
};

local version = 'latest';
local hostPort = '18022';
local containerPort = '7777';

// The world lives under the tree file-browser-quantum serves, so it is reachable from the
// browser as well — hence the shared path out of the registry rather than a local literal.
local worldPath = lib.registry.dir.fileBrowser.shared + '/terraria/worlds/columbia_plaza';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/beardedio/terraria:' + version,
        restart: lib.collections.restart.unlessStopped,
        volumes: [worldPath + ':/config'],
        environment: { world: 'Columbia_Plaza.wld' },
        ports: ['%s:%s:%s' % [lib.collections.ip.loopback, hostPort, containerPort]],
        tty: true,
        stdin_open: true,
      },
    },
  },
}
