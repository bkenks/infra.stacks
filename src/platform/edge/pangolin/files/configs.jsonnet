// Pangolin's four config files. The shapes live in config.libsonnet, which is parameterized
// by the domain this instance is reached at (host = pangolin.<urlDomain>) and whose four
// keys are the four files rendered here.
local lib = import 'lib.libsonnet';

(import 'config.libsonnet')(lib.collections.domain.ktbcloud)
