// dynamic_config.jsonnet — SOURCE for dynamic_config.yaml (Traefik dynamic
// config: routers/services/middlewares for this edge host).
//
// Renders (via .jsonnet/render.py) to dynamic_config.yaml, mounted read-only
// into the traefik container at /etc/traefik/dynamic_config.yml (see
// compose.stack.jsonnet — the container path keeps the .yml name that traefik's
// file provider points at; only the git-tracked source basename is .yaml). DO
// NOT edit dynamic_config.yaml — edit this source and re-render.
//
// ⚠️ safe_dump strips YAML comments, so dynamic_config.yaml carries only the
// render.py DO-NOT-EDIT header — all operational knowledge lives HERE.
//
// The Host() rules and the wildcard cert derive from reg.domains.ktbinternal, so
// a domain migration follows automatically. The backend hostnames stay the
// literal 'pangolin' — pangolin/gerbil/traefik hardcode each other's service
// names and are deliberately NOT run through lib.compose.names() (see the stack
// README and compose.stack.jsonnet's naming-deviation note).
local lib = import 'lib.libsonnet';
local reg = lib.registry;

local baseDomain = reg.domains.ktbinternal;  // ktbinternal.com
local host = 'pangolin.' + baseDomain;       // pangolin.ktbinternal.com

// Cloudflare DNS-01 resolver, shared by every https router below.
local cf = { certResolver: 'cloudflare' };

{
  http: {
    middlewares: {
      badger: {
        plugin: {
          badger: {
            disableForwardAuth: true,
          },
        },
      },
      'redirect-to-https': {
        redirectScheme: {
          scheme: 'https',
        },
      },
    },

    routers: {
      // HTTP -> HTTPS redirect router.
      'main-app-router-redirect': {
        rule: 'Host(`' + host + '`)',
        service: 'next-service',
        entryPoints: ['web'],
        middlewares: ['redirect-to-https', 'badger'],
      },

      // Next.js router (handles everything except API and WebSocket paths).
      // Requests the *.<baseDomain> wildcard here (once) via Cloudflare DNS-01 —
      // same "request once, serve everywhere via SNI" trick as this repo's
      // platform/edge/traefik files/host.yml. Every other router (this stack's
      // api-router/ws-router, and any router Pangolin itself adds dynamically
      // for a new Resource under <baseDomain>) then just needs certResolver:
      // cloudflare with no domains block of its own.
      'next-router': {
        rule: 'Host(`' + host + '`) && !PathPrefix(`/api/v1`)',
        service: 'next-service',
        entryPoints: ['websecure'],
        middlewares: ['badger'],
        tls: cf {
          domains: [
            { main: baseDomain, sans: ['*.' + baseDomain] },
          ],
        },
      },

      // API router (handles /api/v1 paths).
      'api-router': {
        rule: 'Host(`' + host + '`) && PathPrefix(`/api/v1`)',
        service: 'api-service',
        entryPoints: ['websecure'],
        middlewares: ['badger'],
        tls: cf,
      },

      // WebSocket router.
      'ws-router': {
        rule: 'Host(`' + host + '`)',
        service: 'api-service',
        entryPoints: ['websecure'],
        middlewares: ['badger'],
        tls: cf,
      },
    },

    services: {
      'next-service': {
        loadBalancer: { servers: [{ url: 'http://pangolin:3002' }] },  // Next.js server
      },
      'api-service': {
        loadBalancer: { servers: [{ url: 'http://pangolin:3000' }] },  // API/WebSocket server
      },
    },
  },

  tcp: {
    serversTransports: {
      'pp-transport-v1': { proxyProtocol: { version: 1 } },
      'pp-transport-v2': { proxyProtocol: { version: 2 } },
    },
  },
}
