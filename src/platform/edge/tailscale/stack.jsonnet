// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// SETUP
// —————————————————————
// IMPORTS
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;
local sharedNetworks = reg.networks.shared;
// IMPORTS
// —————————————————————


// —————————————————————
// CONFIGURATION VARIABLES
// — stack —
local name = 'ts-dokr-gw';
local sharedTSGateway = sharedNetworks.tsGateway;
local secrets = [ lib.Secret('tsGateway') ];
// — services —
local appVersion = 'v1.98.9';
// CONFIGURATION VARIABLES
// —————————————————————
// SETUP
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// DEFINE
local services(ref) = {
  [role.APP]: lib.Service {
    # — config: container —
    image: 'tailscale/tailscale:' + appVersion, restart: reg.restartPolicy.default,
    # - config: image —
    environment: {
      TS_AUTHKEY:       '${TS_AUTHKEY:?err}',
      TS_HOSTNAME:      name + '_${HOST}',
      TS_STATE_DIR:     '/var/lib/tailscale',
      TS_USERSPACE:     'true',
      TS_EXTRA_ARGS:    '--advertise-tags=tag:gateway'
    },
    # — resources —
    volumes_:: { app: '/var/lib/tailscale' }, networks_:: lib.network.join(reg.networks.shared.tsGateway),

}};

local stack = lib.Stack(
  name, services,
  lib.network.create(sharedTSGateway)
);
// DEFINE
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// SCAFFOLD
lib.render(name, stack, secrets)
// SCAFFOLD
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
