// The tree this stack serves is shared: terraria keeps its world under
// registry.dirs.fileBrowser.shared, so the paths come from the registry, not from here.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local appVersion = 'stable';
local initVersion = '3.24.1';
local publicPort = '18450';
local appPort = '80';
local dir = lib.registry.dirs.fileBrowser;

local initScript = std.join(' && ', [
  'mkdir -p ' + dir.data,
  'mkdir -p ' + dir.shared,
  'mkdir -p ' + dir.cache,
  'chown -R 1000:0 ' + dir.root,
  'chmod -R 770 ' + dir.root,
]);

{
  name: refs.name,
  networks: refs.networks,

  services: {
    [refs.init.key]: {
      container_name: refs.init.container,
      image: 'alpine:' + initVersion,
      // Quoted: bare `no` is a YAML boolean and compose wants the string.
      restart: 'no',
      user: 'root',
      volumes: [lib.dirs.rootlessSrv + ':' + lib.dirs.rootlessSrv],
      command: ['sh', '-c', initScript],
    },

    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'gtstef/filebrowser:' + appVersion,
      restart: lib.restart.unlessStopped,
      depends_on: {
        [refs.init.key]: { condition: lib.condition.completed },
      },
      volumes: [
        './files/config.yaml:/home/filebrowser/data/config.yaml:ro',
        dir.data + ':/data',
        dir.shared + ':/shared',
        dir.cache + ':/cache',
      ],
      expose: [appPort],
      ports: ['%s:%s:%s' % [lib.ip.loopback, publicPort, appPort]],
    },
  },
}
