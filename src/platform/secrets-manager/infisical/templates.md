# Templates

## Agent Configuration File: Template YAML Blocks

```yaml
- destination-path: /dev/shm/arcane.env
  config:
    polling-interval: "1m"
  template-content: |
    {{}}
```

**Or:**

```yaml
- source-path: my-go-template
  destination-path: /dev/shm/arcane.env
  config:
    polling-interval: "1m"
```

**Or:**

```yaml
- destination-path: /dev/shm/databasus_secret.key
  config:
    polling-interval: "1m"
  template-content: |
    {{- with getSecretByName "86324d9b-3dd7-49d4-b252-69228c5ee0c7" "prod" "/databasus" "SECRET_KEY" -}}{{ .Value }}{{- end -}}
```

## Secrets: Go Templates Blocks

### Dump Folder

**Template:**

```go
{{- with listSecrets "<project-id>" "<environment-slug>" "<path-to-secret-folder>" }}
{{- range . }}
{{ .Key }}={{ .Value }}
{{- end }}
{{- end }}
```

**Example:**

```go
{{- with listSecrets "86324d9b-3dd7-49d4-b252-69228c5ee0c7" "prod" "/arcane" }}
{{- range . }}
{{ .Key }}={{ .Value }}
{{- end }}
{{- end }}
```

### Raw

**Template:**

```go
{{- with getSecretByName "<project-id>" "<environment-slug>" "<path-to-secret-folder>" "<secret-name>" -}}{{ .Value }}{{- end -}}
```

**Example:**

```go
{{- with getSecretByName "86324d9b-3dd7-49d4-b252-69228c5ee0c7" "prod" "/databasus" "PG_TOKEN" -}}{{ .Value }}{{- end -}}
```
