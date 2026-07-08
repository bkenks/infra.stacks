// Renders to dynamic_config.yaml, mounted read-only into traefik at
// /etc/traefik/dynamic_config.yml. Edit this source, not the yaml — safe_dump strips
// comments, so the yaml carries only a DO-NOT-EDIT header and all operational knowledge
// lives HERE. Backend hostnames stay literal 'pangolin' — see compose.stack.jsonnet's
// naming-deviation note.
local reg = import 'registry.libsonnet';

local baseDomain = reg.domains.ktbinternal;
local host = 'pangolin.' + baseDomain;

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
      'main-app-router-redirect': {
        rule: 'Host(`' + host + '`)',
        service: 'next-service',
        entryPoints: ['web'],
        middlewares: ['redirect-to-https', 'badger'],
      },

      // Requests the *.<baseDomain> wildcard here (once) via Cloudflare DNS-01 — same
      // "request once, serve everywhere via SNI" trick as platform/edge/traefik files/host.yml.
      // Every other router then just needs certResolver: cloudflare with no domains block.
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

      'api-router': {
        rule: 'Host(`' + host + '`) && PathPrefix(`/api/v1`)',
        service: 'api-service',
        entryPoints: ['websecure'],
        middlewares: ['badger'],
        tls: cf,
      },

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
