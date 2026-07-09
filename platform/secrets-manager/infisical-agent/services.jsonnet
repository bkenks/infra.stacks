// Generates templates/<svc>.yaml, one self-contained Infisical-agent config fragment per
// service (multi-file output via `jsonnet -S -m`; see .jsonnet/render.py). Source of truth
// is the registry — edit there, NOT the generated templates/.
//
// Each fragment is a complete `templates:` list entry with INLINE template-content, so
// entrypoint.sh just `cat`s the fragments under one `templates:` header (substituting
// ${AGENT_HOST} — the one runtime-only value — since the agent's template engine has no
// env access).
//
//   type=dump  whole Infisical folder -> KEY=VALUE (secret names == env names)
//   type=map   explicit OUTPUT=FROM renames/duplications (registry `keys`)
//   type=raw   a single secret's raw value, no KEY= prefix (registry `key`)
local reg = import 'registry.libsonnet';

local bodyLines(s) =
  local project = reg.infisical.projects[s.project];
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
local fragment(s) =
  '# GENERATED from services.jsonnet by .jsonnet/render.py — DO NOT EDIT.\n' +
  '- destination-path: /dev/shm/' + s.dest + '\n' +
  '  config:\n' +
  '    polling-interval: "1m"\n' +
  '  template-content: |\n' +
  indentBody(s) + '\n';

{
  [name + '.yaml']: fragment(reg.infisical.services[name])
  for name in std.objectFields(reg.infisical.services)
}
