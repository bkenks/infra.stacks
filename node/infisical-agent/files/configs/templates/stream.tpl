{{- $p := "2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47" -}}
{{- $e := "prod" -}}
{{- $path := "/stream" -}}
SONARR_API_KEY={{ with getSecretByName $p $e $path "SONARR_API_KEY" }}{{ .Value }}{{ end }}
RADARR_API_KEY={{ with getSecretByName $p $e $path "RADARR_API_KEY" }}{{ .Value }}{{ end }}
