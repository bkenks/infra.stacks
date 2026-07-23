// Renders Pangolin's three config files for this instance, reached at pangolin.ktbcloud.com.
// The whole shape is config.libsonnet; the only knob is the domain passed here.
local reg = import 'lib/registry.libsonnet';
(import 'config.libsonnet')(reg.domains.ktbcloud)
