// ryshe/terraria tags a TShock release together with the Terraria version it targets, and
// the pair is not free to vary: a TShock build supports exactly one Terraria version.
// 1.4.5.6 is what the vanilla `terraria` stack already runs, so the world and every client
// carry over untouched. beardedio (the vanilla stack's image) has no TShock 6.x build.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'terraria-tshock',

  app:: self.Service { role:: lib.collections.role.APP },
};

local imageTag = 'tshock-1.4.5.6-6.1.0';

local gamePort = '7777';
local restPort = '7878';

// Its own host ports and its own host directory, so this runs alongside `terraria` instead
// of fighting it. Two servers opening one .wld corrupts it, so the world is copied in, not
// shared — see README.
local gameHostPort = '18023';
local restHostPort = '18024';
local dataPath = lib.collections.dirs.rootlessSrv + '/terraria-tshock';

// The image defaults CONFIGPATH to the worlds directory, which buries tshock.sqlite — the
// only copy of every server-side character — among the .wld files. Split them so the thing
// that must be backed up is one directory.
local configDir = '/tshock/config';
local worldsDir = '/root/.local/share/Terraria/Worlds';
local logsDir = '/tshock/logs';
local pluginsDir = '/tshock/ServerPlugins';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ryshe/terraria:' + imageTag,
        restart: lib.collections.restart.unlessStopped,
        ports: [
          '%s:%s:%s' % [lib.collections.ip.loopback, gameHostPort, gamePort],
          // A REST token is full server admin, including arbitrary console commands, so this
          // stays on loopback like the game port. Anything consuming it joins this stack's
          // network rather than dialling the host.
          '%s:%s:%s' % [lib.collections.ip.loopback, restHostPort, restPort],
        ],
        environment: {
          WORLD_FILENAME: 'Columbia_Plaza.wld',
          CONFIGPATH: configDir,
          LOGPATH: logsDir,
        },
        volumes: [
          dataPath + '/config:' + configDir,
          dataPath + '/worlds:' + worldsDir,
          dataPath + '/logs:' + logsDir,
          dataPath + '/plugins:' + pluginsDir,
        ],
        // TShock reads console commands on stdin; without a TTY the server exits at startup.
        tty: true,
        stdin_open: true,
      },
    },
  },
}
