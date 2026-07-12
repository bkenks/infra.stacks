// Renders files/hosts from registry.libsonnet's server.hosts — the single source of truth
// for host → IP. Add/rename/re-IP a host there and it flows here on re-render (lefthook
// re-renders every stack when a lib changes). dnsmasq serves these via addn-hosts; once the
// file reaches the host, SIGHUP the container to reload without redeploying anything.
local reg = import 'registry.libsonnet';

local hosts = reg.server.hosts;

// Entries not derived from the inventory: the healthcheck sentinel, plus any one-off pins.
local extra = [
  { ip: '127.0.0.1', name: 'health.check.dnsmasq' },  // healthcheck sentinel — keep
];

local entries =
  [{ ip: hosts[h].ip, name: h } for h in std.objectFields(hosts)] + extra;

local body = std.join('', [
  '%s  %s\n' % [e.ip, e.name]
  for e in entries
]);

{
  hosts: '# Source: registry.libsonnet server.hosts (+ sentinel) — edit there, not here.\n' + body,
}
