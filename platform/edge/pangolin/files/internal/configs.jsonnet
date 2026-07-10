// internal variant — reached at pangolin.ktbinternal.com (bill).
// The whole shape is ../config.libsonnet; the only knob is the domain passed here.
local reg = import 'registry.libsonnet';
(import '../config.libsonnet')(reg.domains.ktbinternal)
