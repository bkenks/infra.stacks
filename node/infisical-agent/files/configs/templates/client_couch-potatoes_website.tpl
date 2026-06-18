{{- $p := "fb1dd6a7-3924-415b-b6c3-3071fc93aaae" -}}
{{- $e := "prod" -}}
{{- $path := "/website" -}}
PAYLOAD_SECRET={{ with getSecretByName $p $e $path "PAYLOAD_SECRET" }}{{ .Value }}{{ end }}
