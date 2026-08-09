local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'terraria';

local version = 'latest';
local hostPort = 18022;
local containerPort = 7777;

local configPath = reg.dirs.general.rootlessSrv + '/terraria/config';

lib.render(
  name,

  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/beardedio/terraria:' + version,
      ports: ['%s:%d:%d' % [reg.ips.loopback, hostPort, containerPort]],
      environment: { world: 'Columbia_Plaza.wld.wld' },
      restart: reg.restartPolicy.unlessStopped,
      mounts_:: [ configPath + ':/config'],
      tty: true,
      stdin_open: true,
    },
  }),
)
