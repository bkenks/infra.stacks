// compose.libsonnet
//
// Helpers for building docker-compose fragments that reference the registry.
// Import via the umbrella (lib.compose.*) or directly.
local reg = import 'registry.libsonnet';

// File-private alias for the shared-networks registry. The real Docker name
// (with its explicit 'shared-' prefix) lives in each entry's `.name`.
local sharedNetworks = reg.sharedNetworks;

{
  // CONSUMER: join an existing shared network. external:true means it must
  // already exist, so the OWNER stack has to deploy first.
  //   networks: compose.join('proxy')
  join(key):: { [sharedNetworks[key].name]: { external: true, name: sharedNetworks[key].name } },

  // OWNER: create the shared network this stack owns (registry records who).
  //   networks: compose.own('dbBackups')
  own(key):: { [sharedNetworks[key].name]: { name: sharedNetworks[key].name } },

  serviceNetwork(network, alias) :: {
        [network]: { aliases: [ alias ] },
  },

  // ── Cross-container addressing ──────────────────────────────────────────
  // A service other stacks dial publishes a registry endpoint (private/public).
  // The OWNER names itself from it; CONSUMERS read it. So the address lives once.

  // PRIVATE container-to-container URL (same host, shared network):
  //   privateUrl('infisical') -> 'http://infisical-app:8080'
  privateUrl(key, scheme='http')::
    local e = reg.endpoints[key].private;
    scheme + '://' + e.host + ':' + std.toString(e.port),

  // PUBLIC URL via Traefik (any host, https on the wildcard cert). The zone
  // comes from the endpoint's domain (pulled from the domains registry):
  //   publicUrl('infisical') -> 'https://infisical.homektb.com'
  publicUrl(key):: 'https://' + reg.endpoints[key].public.sub + '.' + reg.endpoints[key].public.domain,

  // Consistent stack-local naming, following the KTB naming convention
  // (<stack>_<role> — underscore separates ownership levels; dashes are only
  // for multi-word names within one level, e.g. 'komodo-periphery').
  // Pass a role constant (registry.roles.app) or any string (container('core'),
  // volume('keys'), alias('mongo')). container/volume/alias are the same
  // machinery — the name just labels intent at the call site.
  //
  // Volumes: pass the SERVICE's role when it owns exactly one volume (the
  // volume's resource key and container's role must match — see
  // docker-compose.md's "Resources" section), or '<role>_<purpose>' when a
  // service owns more than one (e.g. volume(app + '_data')).
  //
  // Names are generated, never hand-typed.
  names(stack):: {
    stack:: stack,
    // This stack's PRIVATE network: the auto 'default' net renamed to the stack
    // name. Drop into `networks:` (merge shared sharedNetworks with +). Other compose
    // projects can't attach (not external) — that's the isolation; this is
    // project isolation, NOT docker's `internal: true` (which blocks egress).
    //   networks: n.network
    //   networks: n.network + compose.own('postgres') + compose.join('dbBackups')
    network:: { default: { name: stack } },
    container(role):: stack + '_' + role,
    volume(role):: stack + '_' + role,
    alias(role):: stack + '_' + role,
  },
}
