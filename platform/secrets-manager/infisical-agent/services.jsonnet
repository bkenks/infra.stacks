// services.jsonnet — generates templates/<svc>.yaml, one self-contained
// Infisical-agent config fragment per service (multi-file output via
// `jsonnet -S -m`; see .jsonnet/render.py).
//
// Source of truth is the registry
// Edit there, NOT the generated templates/ — those files are GENERATED.
//
// Each fragment is a complete `templates:` list ENTRY with an INLINE
// `template-content`, so entrypoint.sh no longer builds Go templates in shell:
// it just `cat`s the fragments named in AGENT_SERVICES under a `templates:`
// header (and substitutes ${AGENT_HOST}, the one runtime-only value, on the way
// in — the agent's template engine has no env access).
//
//   type=dump  whole Infisical folder -> KEY=VALUE (secret names == env names)
//   type=map   explicit OUTPUT=FROM renames/duplications (registry `keys`)
//   type=raw   a single secret's raw value, no KEY= prefix (registry `key`)
local reg = import 'registry.libsonnet';

// The Go-template body (list of lines, unindented) for one service, by type.
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

// Indent each body line by 4 spaces for the YAML `template-content: |` scalar.
local indentBody(s) = std.join('\n', ['    ' + l for l in bodyLines(s)]);

// One complete `templates:` list entry (rendered as raw YAML, not via
// manifestYamlDoc, so the Go-template bytes are exact and auditable).
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
