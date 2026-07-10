// Per-instance knobs for this Pangolin edge, imported by BOTH compose.jsonnet and
// files/configs.jsonnet so the two renders can never disagree about which zone this
// instance serves. The stack shape itself lives in platform/edge/pangolin.libsonnet.
//
// This instance: bill, serving the ktbinternal.com plane. Its sibling is
// platform/edge/pangolin.
local reg = import 'registry.libsonnet';

{
  stack: 'pangolin-internal',
  baseDomain: reg.domains.ktbinternal,

  // Its own Infisical folder: a SERVER_SECRET shared with the ktbcloud instance would let
  // either one mint session tokens the other accepts.
  secret: reg.infisical.services['pangolin-internal'],

  // Authentik runs on rick, not here. Leaving this false keeps the stack off the external
  // shared-edge network (which only the authentik stack creates) and drops the auth router.
  // This instance still uses Authentik as its IdP — over the public internet at
  // https://auth.ktbcloud.com, not over shared-edge.
  servesAuthentik: false,
}
