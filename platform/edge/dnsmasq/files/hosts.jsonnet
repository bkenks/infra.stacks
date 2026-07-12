// Renders files/hosts from registry.libsonnet's server.hosts — the single source of truth
// for every host's name(s) → IP(s). Each host emits one line per address; addresses are
// ordered LAN-first (Tailscale as fallback) or, for VPS hosts, Tailscale-first (public as
// fallback), so a name still resolves if the preferred path is down. dnsmasq serves these
// via addn-hosts; once the file reaches the host, SIGHUP the container to reload — no redeploy.
local reg = import 'registry.libsonnet';

local hosts = reg.server.hosts;

// Address order per host: LAN before Tailscale; Tailscale before public (VPS). The preferred
// address is emitted first so clients try it first, with the other(s) as fallback.
local addrs(h) =
  (if std.objectHas(h, 'lan') then [h.lan] else [])
  + [h.ip]
  + (if std.objectHas(h, 'public') then [h.public] else []);

// Names for a host: <name>.internal FQDN, the short name, then any aliases. `dns` overrides
// the registry key when the DNS name differs from it (e.g. paiki → plexyandiknowit).
local names(key, h) =
  local base = if std.objectHas(h, 'dns') then h.dns else key;
  [base + '.internal', base] + (if std.objectHas(h, 'aka') then h.aka else []);

local hostBlock(key) =
  local h = hosts[key];
  local nameStr = std.join(' ', names(key, h));
  std.join('', [
    '%s\t%s\n' % [ip, nameStr]
    for ip in addrs(h)
  ]);

local body = std.join('', [
  hostBlock(key)
  for key in std.objectFields(hosts)
]);

{
  hosts:
    '# Source: registry.libsonnet server.hosts — edit there, not here.\n'
    + '# One line per address: LAN/Tailscale (or Tailscale/public for VPS), preferred first.\n'
    + body
    + '# Healthcheck sentinel — the container healthcheck resolves this name.\n'
    + '127.0.0.1\thealth.check.dnsmasq\n',
}
