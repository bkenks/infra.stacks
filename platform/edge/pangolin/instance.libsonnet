// Per-instance knobs for this Pangolin edge, imported by BOTH compose.jsonnet and
// files/configs.jsonnet so the two renders can never disagree about which zone this
// instance serves. The stack shape itself lives in platform/edge/pangolin.libsonnet.
//
// This instance: rick (the VPS), serving the public ktbcloud.com plane, colocated with
// Authentik. Its sibling is platform/edge/pangolin-internal.
local reg = import 'registry.libsonnet';

{
  stack: 'pangolin',
  baseDomain: reg.domains.ktbcloud,
  secret: reg.infisical.services.pangolin,

  // Authentik lives on this host, so this instance fronts auth.ktbcloud.com and joins
  // shared-edge to reach it.
  servesAuthentik: true,

  // Pinned, not defaulted: rick already has live state under bind-mounts/pangolin
  // (Gerbil's WireGuard key, Pangolin's db, acme.json). Keep the path even though the
  // instance is now the ktbcloud one.
  dataDir: 'pangolin',
}
