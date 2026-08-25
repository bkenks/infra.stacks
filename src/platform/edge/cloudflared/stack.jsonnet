// Cloudflare Tunnel egress; apps are reached via their exposed ports.
//
// The bundle is per-host (/hosts/${AGENT_HOST}/cloudflared), so the deploy environment has
// to carry AGENT_HOST — compose interpolates it into the provider's path before the
// provider runs.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'cloudflared',

  tunnel:: self.Service { role:: lib.collections.role.TUNNEL },
};

local version = '2026.5.2';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('cloudflared'),

      [refs.tunnel.key]: {
        container_name: refs.tunnel.ext,
        image: 'cloudflare/cloudflared:' + version,
        restart: lib.collections.restart.unlessStopped,
        command: 'tunnel --no-autoupdate run',
        depends_on: lib.secretsReady,
        // TUNNEL_TOKEN arrives from infisical-secrets.
        environment: {
          TZ: 'America/New_York',
        },
      },
    },
  },
}
