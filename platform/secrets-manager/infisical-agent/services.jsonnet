// services.jsonnet — generates services.yaml, the Infisical-agent secret
// catalogue (mounted into the container; entrypoint.sh reads it).
//
// Source of truth is the registry's `agentServices` (+ `projects` for UUIDs).
// Edit there, NOT services.yaml — that file is GENERATED. The project KEY is
// resolved to its UUID here. For type=map the structured `keys` object is
// flattened to a space-separated "OUT=FROM" string (easy for entrypoint.sh's
// awk parser); for type=raw the single `key` is passed through.
local reg = import 'registry.libsonnet';

// { OUT: 'FROM', ... } -> "OUT=FROM OUT2=FROM2" (sorted; order is irrelevant for env)
local flattenKeys(m) = std.join(' ', [k + '=' + m[k] for k in std.objectFields(m)]);

local entry(s) = {
  project: reg.projects[s.project],
  env: std.get(s, 'env', 'prod'),
  folder: s.folder,
  dest: s.dest,
  type: s.type,
} + (
  if s.type == 'map' then { keys: flattenKeys(s.keys) }
  else if s.type == 'raw' then { key: s.key }
  else {}
);

{
  services: {
    [name]: entry(reg.agentServices[name])
    for name in std.objectFields(reg.agentServices)
  },
}
