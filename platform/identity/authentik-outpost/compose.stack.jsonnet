// Dials the core Authentik server OUTBOUND and serves the forward-auth endpoint on :9000,
// published on the host so every mesh host's Traefik can forward-auth to it over Tailscale.
local c = import 'compose.libsonnet';

local stack = 'authentik-outpost';
local s = c.stack(stack);
local n = s.names;

local version = '2026.5.3';  // pin == authentik/compose.stack.jsonnet's server version
local role = 'proxy';
local extName = n.container(role);

{
  name: stack,

  services: {
    [role]: {
      image: 'ghcr.io/goauthentik/proxy:' + version,
      container_name: extName,
      restart: 'unless-stopped',
      environment: {
        AUTHENTIK_HOST: 'https://auth.ktbcloud.com',
        AUTHENTIK_INSECURE: 'false',
        AUTHENTIK_TOKEN: '${AUTHENTIK_TOKEN:?err}',
      },
      // Published so remote-host Traefiks reach it at <tailscale-ip>:9000.
      ports: ['9000:9000'],
      networks: { default: { aliases: [extName] } },
    },
  },

  networks: s.network.default,
}
