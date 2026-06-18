{{- $p := "2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47" -}}
{{- $e := "prod" -}}
{{- $path := "/docuseal" -}}
DOCUSEAL_SECRET_KEY_BASE={{ with getSecretByName $p $e $path "DOCUSEAL_SECRET_KEY_BASE" }}{{ .Value }}{{ end }}
