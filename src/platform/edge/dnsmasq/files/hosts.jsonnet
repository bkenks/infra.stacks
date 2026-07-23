// Renders files/hosts from registry.libsonnet's `hosts` — the single source of truth
// for every host's name(s) → IP(s). Each host emits one line per address; addresses are
// ordered LAN-first (Tailscale as fallback) or, for VPS hosts, Tailscale-first (public as
// fallback), so a name still resolves if the preferred path is down. dnsmasq serves these
// via addn-hosts; once the file reaches the host, SIGHUP the container to reload — no redeploy.
local reg = import 'lib/registry.libsonnet';

local hosts = reg.hosts;

// Address order per host: LAN before Tailscale; Tailscale before public (VPS). The preferred
// address is emitted first so clients try it first, with the other(s) as fallback.
local addrs(h) =
  (if std.objectHas(h, 'lan') then [h.lan] else [])
  + [h.ip]
  + (if std.objectHas(h, 'public') then [h.public] else []);

// Names for a host: every name is a <name>.ktbinternal.com FQDN — the base name plus any
// aliases, each suffixed with the internal domain. `dns` overrides the registry key when the
// DNS name differs from it (e.g. paiki → plexyandiknowit); `aka` supplies extra aliases
// (e.g. littlebuddy → controlplane.ktbinternal.com).
local domain = 'srv';
local names(key, h) =
  local base = if std.objectHas(h, 'dns') then h.dns else key;
  local shortNames = [base] + (if std.objectHas(h, 'aka') then h.aka else []);
  [n + '.' + domain for n in shortNames];

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
    '# Source: registry.libsonnet hosts — edit there, not here.\n'
    + '# One line per address: LAN/Tailscale (or Tailscale/public for VPS), preferred first.\n'
    + body
    + '# Healthcheck sentinel — the container healthcheck resolves this name.\n'
    + '127.0.0.1\thealth.check.dnsmasq\n',
}
