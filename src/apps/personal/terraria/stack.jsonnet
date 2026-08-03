local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'terraria';

local version = 'latest';
local hostPort = 18022;
local containerPort = 7777;

lib.render(
  name,

  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/beardedio/terraria:' + version,
      ports: ['%s:%d:%d' % [reg.ips.loopback, hostPort, containerPort]],
      environment: { world: 'choobtown.wld' },
      restart: reg.restartPolicy.unlessStopped,
      mounts_:: ['/srv/docker/volumes/games/terraria/config:/config'],
      tty: true,
      stdin_open: true,
    },
  }, { default: { name: 'internal' } }),
)
