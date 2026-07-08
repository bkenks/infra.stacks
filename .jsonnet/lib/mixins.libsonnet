// mixins.libsonnet
//
// Reusable service / label fragments. Merge into a service or labels map with `+`.
local reg = import 'registry.libsonnet';

{
  // NOTE: secrets are delivered by INTERPOLATION, not injection. Each stack lists
  // its secret vars as ${VAR:?err} under a `# Secrets` comment in compose.jsonnet;
  // the per-stack parent compose.yaml declares the interpolation source via
  // `include.env_file` (the Infisical-agent-rendered /dev/shm file). So there is
  // no secretsEnv mixin — nothing injects a whole secret file into a container.

  // Standard single-router Traefik labels for a service behind this host's
  // Traefik on the wildcard *.<domain> cert.
  //   router: unique router/service id     sub: subdomain (sub.<domain>)
  //   port:   container port to load-balance to
  //   domain: a domains-registry KEY (e.g. 'stackform') that resolves to its
  //           zone, OR a literal zone string. Defaults to rootDomain (homektb).
  proxyAdd(router, sub, port, domain=reg.rootDomain)::
    // Resolve a registry key ('stackform' -> 'stackform.app'); pass through if
    // it's already a literal zone (the rootDomain default included).
    local zone = if std.objectHas(reg.domains, domain) then reg.domains[domain] else domain;
    {
      'traefik.enable': 'true',
      ['traefik.http.routers.' + router + '.rule']: 'Host(`' + sub + '.' + zone + '`)',
      ['traefik.http.routers.' + router + '.entrypoints']: 'websecure',
      ['traefik.http.routers.' + router + '.tls']: 'true',
      ['traefik.http.services.' + router + '.loadbalancer.server.port']: std.toString(port),
    },

  // Same as proxyAdd, plus the Authentik forward-auth middleware — gates the
  // router behind SSO. The `authentik-forwardauth@file` middleware is defined in
  // Traefik's file provider (points at the authentik-outpost); it's referenced
  // here but wired at Phase 2, not by this scaffolding.
  proxyAddAuth(router, sub, port, domain=reg.rootDomain)::
    self.proxyAdd(router, sub, port, domain) + {
      ['traefik.http.routers.' + router + '.middlewares']: 'authentik-forwardauth@file',
    },

  // Marks a container so Komodo's StopAllContainers leaves it running.
  komodoSkip:: { 'komodo.skip': '' },
}
