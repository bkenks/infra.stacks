// Generates <svc>.yaml beside this file, one self-contained Infisical-agent config fragment
// per service. Source of truth is the registry — edit there, NOT the generated fragments.
//
// Each fragment is a complete `templates:` list entry with INLINE template-content, so
// entrypoint.sh just `cat`s the fragments under one `templates:` header (substituting
// ${AGENT_HOST} — the one runtime-only value — since the agent's template engine has no
// env access).
//
//   type=dump  whole Infisical folder -> KEY=VALUE (secret names == env names)
//   type=map   explicit OUTPUT=FROM renames/duplications (registry `keys`)
//   type=raw   a single secret's raw value, no KEY= prefix (registry `key`)
local lib = import 'lib.libsonnet';
local reg = lib.registry;

local bodyLines(s) =
  local project = reg.infisical.project[s.project];
  local env = std.get(s, 'env', 'prod');
  local folder = s.folder;

  if s.type == 'dump' then [
    '{{- with listSecrets "' + project + '" "' + env + '" "' + folder + '" }}',
    '{{- range . }}',
    '{{ .Key }}={{ .Value }}',
    '{{- end }}',
    '{{- end }}',
  ] else if s.type == 'map' then [
    out + '={{ with getSecretByName "' + project + '" "' + env + '" "' + folder + '" "' + s.keys[out] + '" }}{{ .Value }}{{ end }}'
    for out in std.objectFields(s.keys)
  ] else [  // raw
    '{{- with getSecretByName "' + project + '" "' + env + '" "' + folder + '" "' + s.key + '" -}}{{ .Value }}{{- end -}}',
  ];

// 4-space indent required by the YAML `template-content: |` block scalar.
local indentBody(s) = std.join('\n', ['    ' + l for l in bodyLines(s)]);

// Built as a raw string, not via manifestYamlDoc, so the Go-template bytes stay exact.
// render.py prepends the GENERATED header to every output; do not add one here.
// Ends on a blank line, separating the fragments entrypoint.sh cats together.
local fragment(name) =
  local s = reg.infisical.catalog[name];
  '- destination-path: ' + lib.Secret(name) + '\n' +
  '  config:\n' +
  '    polling-interval: "1m"\n' +
  '  template-content: |\n' +
  indentBody(s) + '\n\n';

{
  [name + '.yaml']: fragment(name)

  for name in std.objectFields(reg.infisical.catalog)
}
