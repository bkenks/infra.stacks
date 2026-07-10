// cloud variant — reached at pangolin.ktbcloud.com (rick, the VPS).
// The whole shape is ../config.libsonnet; the only knob is the domain passed here.
local reg = import 'registry.libsonnet';
(import '../config.libsonnet')(reg.domains.ktbcloud)
