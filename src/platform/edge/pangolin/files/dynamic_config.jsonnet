// One of Pangolin's four config files; the shape lives in config.libsonnet, which is
// parameterized by the domain this instance is reached at.
local lib = import 'lib.libsonnet';
(import 'config.libsonnet')(lib.domain.ktbcloud).dynamic_config
