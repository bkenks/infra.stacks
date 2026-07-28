// NEWT_ID/NEWT_SECRET come from /dev/shm/newt.env (infisical-agent); PANGOLIN_ENDPOINT
// (the control-server URL) comes from the committed ./envs/env.newt.env rendered by env.jsonnet.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'newt';
local version = '1.14.0';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.TUNNEL]: lib.Service {
      image: 'fosrl/newt:' + version,
      extra_hosts: ['host.docker.internal:host-gateway'],
      env_file: ['./envs/env.newt.env'],  // PANGOLIN_ENDPOINT (control-server URL)
      environment: {
        TZ: 'America/New_York',
        NEWT_ID: '${NEWT_ID:?err}',
        NEWT_SECRET: '${NEWT_SECRET:?err}',
      },
    },
  }),
  [lib.Secret('newt')],
)
