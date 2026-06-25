{{- $p := "86324d9b-3dd7-49d4-b252-69228c5ee0c7" -}}
{{- $e := "prod" -}}
{{- $path := "/databasus" -}}
{{- with getSecretByName $p $e $path "SECRET_KEY" -}}{{ .Value }}{{- end -}}
