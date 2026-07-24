local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'pangolin-client';
local appVersion = 'latest';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'fosrl/pangolin-cli:' + appVersion,
      environment: {
        PANGOLIN_ENDPOINT:    reg.endpoint.pangolin.public.url,
        CLIENT_ID:            '${CLIENT_ID:?must provide a client id}',
        CLIENT_SECRET:        '${CLIENT_SECRET:?must provide a client secret}',
      },
      devices: [ '/dev/net/tun:/dev/net/tun' ],
      network_mode: 'host',
      cap_add: [ 'NET_ADMIN' ],
      restart: reg.restartPolicy.default,
    },
  }),
  [lib.Secret('pangolinClient')],
)
