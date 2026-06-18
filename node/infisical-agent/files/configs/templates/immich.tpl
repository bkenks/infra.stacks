{{- $p := "2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47" -}}
{{- $e := "prod" -}}
{{- $path := "/immich" -}}
IMMICH_DB_PASSWORD={{ with getSecretByName $p $e $path "IMMICH_DB_PASSWORD" }}{{ .Value }}{{ end }}
