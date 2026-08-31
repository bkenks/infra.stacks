// The tailnet gateway every stack that needs one attaches to. This stack owns the shared
// network; consumers attach to it.
local lib = import 'lib.libsonnet';
local refs = lib.Project { local project = self,
  name:: 'tailscale-gw',

  app:: self.Service { local app = self,
    role:: lib.collections.role.APP,
    volume:: {
      data:: project.Volume { key:: app.role }
    }  
  },
};

local appVersion = 'v1.98.9';
local gateway = lib.registry.network.shared.tailscale_gw_001;

{
  compose: {
    name: refs.name,
    networks: {
      default: { name: refs.name },
      [gateway.name]: { name: gateway.name },
    },
    volumes: refs.app.volume.data.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/tailscale/containers'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'tailscale/tailscale:' + appVersion,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady,
        networks: ['default', gateway.name],
        volumes: [refs.app.volume.data.mount('/var/lib/tailscale')],
        // TS_AUTHKEY arrives from infisical-secrets. HOST is not a secret — it comes from
        // the deploy environment, so compose still interpolates it here.
        environment: {
          // Per-host, so one stack definition yields a distinct tailnet node per host.
          TS_HOSTNAME: refs.name + '-${HOST:?err}',
          TS_STATE_DIR: '/var/lib/tailscale',
          TS_USERSPACE: 'true',
        },
      },
    },
  },
}
