// Renders files/hosts from registry.libsonnet's `hosts` — the single source of truth
// for every host's name(s) → IP(s). Each address gets its OWN hostname so every name
// maps to exactly one IP (no multi-A round-robin): `<host>.tail.srv` for the Tailscale
// address, `<host>.direct.srv` for the on-network address (LAN for cluster hosts, the
// public IP for VPS hosts). A consumer picks its path by choosing the name. dnsmasq
// serves these via addn-hosts; once the file reaches the host, SIGHUP the container to
// reload — no redeploy.
local reg = import 'lib/registry.libsonnet';

local hosts = reg.hosts;

local domain = 'srv';

// Base short names for a host: the DNS name (the registry key, or the `dns` override
// when the DNS name differs from it — e.g. paiki → plexyandiknowit) plus any `aka`
// aliases (e.g. littlebuddy → controlplane). Each is emitted under both path suffixes.
local shortNames(key, h) =
  local base = if std.objectHas(h, 'dns') then h.dns else key;
  [base] + (if std.objectHas(h, 'aka') then h.aka else []);

// The addresses to publish for a host, each with the suffix that names its path:
// `tail` = the Tailscale IP (always present; the cross-host default), `direct` = the
// on-network IP (LAN, or the public IP for a VPS). A Tailscale-only host emits no
// `.direct` record.
local paths(h) =
  [{ addr: h.ip, suffix: 'tail' }]
  + (
    if std.objectHas(h, 'lan') then [{ addr: h.lan, suffix: 'direct' }]
    else if std.objectHas(h, 'public') then [{ addr: h.public, suffix: 'direct' }]
    else []
  );

local hostBlock(key) =
  local h = hosts[key];
  std.join('', [
    '%s\t%s\n' % [
      p.addr,
      std.join(' ', [n + '.' + p.suffix + '.' + domain for n in shortNames(key, h)]),
    ]
    for p in paths(h)
  ]);

local body = std.join('', [
  hostBlock(key)
  for key in std.objectFields(hosts)
]);

{
  hosts:
    '# Source: registry.libsonnet hosts — edit there, not here.\n'
    + '# Two names per host: <host>.tail.srv (Tailscale IP) and <host>.direct.srv (LAN/public IP).\n'
    + body
    + '# Healthcheck sentinel — the container healthcheck resolves this name.\n'
    + '127.0.0.1\thealth.check.dnsmasq\n',
}
