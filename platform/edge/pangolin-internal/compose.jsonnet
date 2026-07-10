// pangolin-internal — edge on bill: Pangolin (control plane), Gerbil (WireGuard, owns public
// 80/443/51820/21820), Traefik (HTTP routing + ACME) for this edge host only.
//
// NOT the per-host platform/edge/traefik stack — don't deploy both on the same host
// (port conflict; Gerbil owns 80/443 here). bill currently runs traefik_bill, which must be
// retired before this stack can start.
//
// Shape lives in .jsonnet/lib/pangolin.libsonnet; this instance's knobs in ./instance.libsonnet.
local pangolin = import 'pangolin.libsonnet';

pangolin.compose(import './instance.libsonnet')
