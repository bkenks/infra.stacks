{{- $p := "2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47" -}}
{{- $e := "prod" -}}
{{- $path := "/postgres" -}}
POSTGRES_USER={{ with getSecretByName $p $e $path "POSTGRES_USER" }}{{ .Value }}{{ end }}
POSTGRES_PASS={{ with getSecretByName $p $e $path "POSTGRES_PASS" }}{{ .Value }}{{ end }}
PG_ADMIN_PASS={{ with getSecretByName $p $e $path "PG_ADMIN_PASS" }}{{ .Value }}{{ end }}
