local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'terraria';

local version = 'latest';
local hostPort = 18022;
local containerPort = 7777;

local worldPath = reg.dirs.general.rootlessSrv + '/file-browser-quantum/terraria/worlds/columbia_plaza';

lib.render(
  name,

  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/beardedio/terraria:' + version,
      ports: ['%s:%d:%d' % [reg.ips.loopback, hostPort, containerPort]],
      environment: { world: 'Columbia_Plaza.wld' },
      restart: reg.restartPolicy.unlessStopped,
      mounts_:: [ worldPath + ':/config'],
      tty: true,
      stdin_open: true,
    },
  }),
)
