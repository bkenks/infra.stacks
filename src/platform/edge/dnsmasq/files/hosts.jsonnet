// Renders files/hosts from registry.libsonnet's `hosts` — the single source of truth
// for every host's name(s) → IP. Every host is reached at its WireGuard address and
// nothing else, so each host emits exactly one record — `<host>.srv` — and a consumer
// has no path to choose. dnsmasq serves these via addn-hosts; once the file reaches the
// host, SIGHUP the container to reload — no redeploy.
local reg = import 'lib/registry.libsonnet';

local hosts = reg.hosts;

local domain = reg.srvDomain;

// Every name a host answers to: the DNS name (the registry key, or the `dns` override
// when the DNS name differs from it — e.g. paiki → plexyandiknowit) plus any `aka`
// aliases (e.g. littlebuddy → controlplane). All of them resolve to the one address.
local shortNames(key, h) =
  local base = if std.objectHas(h, 'dns') then h.dns else key;
  [base] + (if std.objectHas(h, 'aka') then h.aka else []);

local hostBlock(key) =
  local h = hosts[key];
  '%s\t%s\n' % [
    h.ip,
    std.join(' ', [n + '.' + domain for n in shortNames(key, h)]),
  ];

local body = std.join('', [
  hostBlock(key)
  for key in std.objectFields(hosts)
]);

{
  hosts:
    '# Source: registry.libsonnet hosts — edit there, not here.\n'
    + '# One name per host: <host>.srv → that host\'s WireGuard address.\n'
    + body
    + '# Healthcheck sentinel — the container healthcheck resolves this name.\n'
    + '127.0.0.1\thealth.check.dnsmasq\n',
}
