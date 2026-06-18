{{- $p := "86324d9b-3dd7-49d4-b252-69228c5ee0c7" -}}
{{- $e := "prod" -}}
{{- $path := "/woodpecker" -}}
WOODPECKER_FORGEJO_CLIENT={{ with getSecretByName $p $e $path "WOODPECKER_FORGEJO_CLIENT" }}{{ .Value }}{{ end }}
WOODPECKER_FORGEJO_SECRET={{ with getSecretByName $p $e $path "WOODPECKER_FORGEJO_SECRET" }}{{ .Value }}{{ end }}
WOODPECKER_AGENT_SECRET={{ with getSecretByName $p $e $path "WOODPECKER_AGENT_SECRET" }}{{ .Value }}{{ end }}
