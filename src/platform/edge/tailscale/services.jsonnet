// The tailnet gateway every stack that needs one attaches to. This stack owns the shared
// network; consumers attach to it.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local appVersion = 'v1.98.9';
local gateway = lib.registry.networks.shared.tsGateway;

{
  name: refs.name,
  networks: refs.networks + gateway.create,
  volumes: refs.appData.declare,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'tailscale/tailscale:' + appVersion,
      restart: lib.restart.unlessStopped,
      networks: ['default', gateway.name],
      volumes: [refs.appData.mount('/var/lib/tailscale')],
      environment: {
        TS_AUTHKEY: '${TS_AUTHKEY:?err}',
        // Per-host, so one stack definition yields a distinct tailnet node per host.
        TS_HOSTNAME: refs.name + '--${HOST:?err}',
        TS_STATE_DIR: '/var/lib/tailscale',
        TS_USERSPACE: 'true',
        TS_EXTRA_ARGS: '--advertise-tags=tag:gateway',
      },
    },
  },
}
