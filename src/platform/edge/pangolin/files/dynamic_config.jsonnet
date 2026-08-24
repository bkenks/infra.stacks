// One of Pangolin's four config files; the shape lives in config.libsonnet, which is
// parameterized by the domain this instance is reached at.
local lib = import 'lib.libsonnet';
{
  dynamic_config: (import 'config.libsonnet')(lib.collections.domain.ktbcloud).dynamic_config,
}
