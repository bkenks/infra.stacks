// authentik-outpost — standalone Authentik proxy outpost (forward-auth).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. A single ghcr.io/goauthentik/proxy container that dials the core
// Authentik server OUTBOUND (AUTHENTIK_HOST=https://auth.ktbcloud.com) and
// serves the forward-auth endpoint on :9000. It publishes 9000 on the host so
// every mesh host's Traefik can forward-auth to it over Tailscale.
//
// AUTHENTIK_TOKEN is a secret, interpolated from /dev/shm/authentik-outpost.env
// (declared as the parent compose.yaml include.env_file) — see registry
// agentServices.'authentik-outpost'.
local lib = import 'lib.libsonnet';
local c = lib.compose;

local stack = 'authentik-outpost';
local n = c.names(stack);

local version = '2026.5.3';  // ghcr.io/goauthentik/proxy — pin == server version
local role = 'proxy';
local extName = n.container(role);  // authentik-outpost_proxy

{
  name: stack,

  services: {
    [role]: {
      image: 'ghcr.io/goauthentik/proxy:' + version,
      container_name: extName,
      restart: 'unless-stopped',
      environment: {
        // Non-secret control-plane endpoint (core Authentik server).
        AUTHENTIK_HOST: 'https://auth.ktbcloud.com',
        AUTHENTIK_INSECURE: 'false',
        // Secret — outpost API token, interpolated from
        // /dev/shm/authentik-outpost.env (parent include.env_file).
        AUTHENTIK_TOKEN: '${AUTHENTIK_TOKEN:?err}',
      },
      // Published so remote-host Traefiks reach it at <tailscale-ip>:9000.
      ports: ['9000:9000'],
      networks: { default: { aliases: [extName] } },
    },
  },

  networks: n.network,  // private default net (unused by peers — single service)
}
