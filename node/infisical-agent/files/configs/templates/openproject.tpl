{{- $p := "2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47" -}}
{{- $e := "prod" -}}
{{- $path := "/openproject" -}}
OPEN_PRJ_SECRET_KEY={{ with getSecretByName $p $e $path "OPEN_PRJ_SECRET_KEY" }}{{ .Value }}{{ end }}
COLLAB_SERVER_SECRET={{ with getSecretByName $p $e $path "COLLAB_SERVER_SECRET" }}{{ .Value }}{{ end }}
