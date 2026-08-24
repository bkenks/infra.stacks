// The tailnet gateway every stack that needs one attaches to. This stack owns the shared
// network; consumers attach to it.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local appVersion = 'v1.98.9';
local gateway = lib.registry.network.shared.tsGateway;

{
  // What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
  // services.yaml resolves from it, which a service-level env_file cannot do — that only
  // reaches the container's environment, never the compose document.
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [gateway.name]: { name: gateway.name },
    },
    volumes: refs.appData.declare,

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'tailscale/tailscale:' + appVersion,
        restart: lib.collections.restart.unlessStopped,
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
  },
}
