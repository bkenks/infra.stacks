{{- $p := "2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47" -}}
{{- $e := "prod" -}}
{{- $path := "/paperless" -}}
PAPERLESS_SECRET_KEY={{ with getSecretByName $p $e $path "PAPERLESS_SECRET_KEY" }}{{ .Value }}{{ end }}
PAPERLESS_PG_PASS={{ with getSecretByName $p $e $path "PAPERLESS_PG_PASS" }}{{ .Value }}{{ end }}
