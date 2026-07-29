// coredns — internal split-horizon DNS: serves the `internal.` zone from a static zone
// file, forwards `ts.net` to Tailscale's own resolver, and falls back to public resolvers
// for everything else. Runs on a dedicated bridge with a static IP because DNS clients
// dial it directly by address — there is no proxy in front of a resolver.
//
// Not registered with Komodo (see .nodeploy/) — deployed manually per host. `mise run
// render` still produces compose.yaml / stack.services.yaml so the manifest stays
// the source of truth.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'coredns';
local dnsVersion = '1.14.6';  // verify current tag
local dnsSubnet = '10.200.0.0/24';
local dnsIp = '10.200.0.53';  // must match config/internal.zone's `ns` record

lib.render(
  name,

  lib.Stack(name, function(ref) {
    [role.DNS]: lib.Service {
      image: 'coredns/coredns:' + dnsVersion,
      command: ['-conf', '/etc/coredns/Corefile'],
      mounts_:: [
        './config/Corefile:/etc/coredns/Corefile:ro',
        './config/internal.zone:/etc/coredns/internal.zone:ro',
      ],
      // Merges into the derived alias block rather than replacing it, so the alias stays
      // container_name and this only adds the static address clients outside the stack
      // dial directly.
      networks+: {
        default+: { ipv4_address: dnsIp },
      },
    },
  }, { default: { name: name, ipam: { config: [{ subnet: dnsSubnet }] } } }),
)
