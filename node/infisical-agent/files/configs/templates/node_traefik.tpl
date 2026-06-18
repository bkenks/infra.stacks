{{- $p := "86324d9b-3dd7-49d4-b252-69228c5ee0c7" -}}
{{- $e := "prod" -}}
{{- $path := "/traefik" -}}
CF_DNS_API_TOKEN={{ with getSecretByName $p $e $path "CF_DNS_API_TOKEN" }}{{ .Value }}{{ end }}
