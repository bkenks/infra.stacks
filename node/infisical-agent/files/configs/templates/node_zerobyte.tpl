{{- $p := "86324d9b-3dd7-49d4-b252-69228c5ee0c7" -}}
{{- $e := "prod" -}}
{{- $path := "/zerobyte" -}}
ZEROBYTE_APP_SECRET={{ with getSecretByName $p $e $path "ZEROBYTE_APP_SECRET" }}{{ .Value }}{{ end }}
