// compose.libsonnet
//
// Helpers for building docker-compose fragments that reference the registry.
// Import via the umbrella (lib.compose.*) or directly.
local reg = import 'registry.libsonnet';

// File-private alias for the shared-networks registry. The real Docker name
// (with its explicit 'shared-' prefix) lives in each entry's `.name`.
local nets = reg.sharedNetworks;

{
  // Real Docker name for a shared-network key (errors at compile time if the
  // key is unknown — this is the typo guard).
  netName(key):: nets[key].name,

  // CONSUMER: join an existing shared network. external:true means it must
  // already exist, so the OWNER stack has to deploy first.
  //   networks: compose.join('proxy')
  join(key):: { [nets[key].name]: { external: true, name: nets[key].name } },

  // OWNER: create the shared network this stack owns (registry records who).
  //   networks: compose.own('dbBackups')
  own(key):: { [nets[key].name]: { name: nets[key].name } },

  // Publish a port to the same host port:  publish(4005) -> '4005:4005'
  publish(port):: std.toString(port) + ':' + std.toString(port),

  // ── Cross-container addressing ──────────────────────────────────────────
  // A service other stacks dial publishes a registry endpoint (private/public).
  // The OWNER names itself from it; CONSUMERS read it. So the address lives once.

  // The raw endpoint record: endpoint('infisical') -> { private?, public? }
  endpoint(key):: reg.endpoints[key],

  // PRIVATE container-to-container URL (same host, shared network):
  //   privateUrl('infisical') -> 'http://infisical-app:8080'
  privateUrl(key, scheme='http')::
    local e = reg.endpoints[key].private;
    scheme + '://' + e.host + ':' + std.toString(e.port),

  // PUBLIC URL via Traefik (any host, https on the wildcard cert). The zone
  // comes from the endpoint's domain (pulled from the domains registry):
  //   publicUrl('infisical') -> 'https://infisical.homektb.com'
  publicUrl(key):: 'https://' + reg.endpoints[key].public.sub + '.' + reg.endpoints[key].public.domain,

  // Predefined role constants for the common service roles, so a typo fails at
  // COMPILE time (same guard as registry keys). They're just strings — pass any
  // OTHER role inline when you need one that isn't predefined:
  //   n.container(compose.roles.app)   // predefined, typo-safe
  //   n.volume('keys')                 // arbitrary role, still fine
  roles:: { app: 'app', db: 'db', redis: 'redis' },

  // Consistent stack-local naming, following the EXT_APP_NM convention
  // (<stack>-<role>). Pass a role constant (compose.roles.app) or any string
  // (container('core'), volume('keys'), alias('mongo')). container/volume/alias
  // are the same machinery — the name just labels intent at the call site.
  // Names are generated, never hand-typed.
  names(stack):: {
    stack:: stack,
    // This stack's PRIVATE network: the auto 'default' net renamed to the stack
    // name. Drop into `networks:` (merge shared nets with +). Other compose
    // projects can't attach (not external) — that's the isolation; this is
    // project isolation, NOT docker's `internal: true` (which blocks egress).
    //   networks: n.network
    //   networks: n.network + compose.own('postgres') + compose.join('dbBackups')
    network:: { default: { name: stack } },
    container(role):: stack + '-' + role,
    volume(role):: stack + '-' + role,
    alias(role):: stack + '-' + role,
  },
}
