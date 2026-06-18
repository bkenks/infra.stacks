{{- $p := "15d61370-a2ec-4993-9bbd-3774a63f7b94" -}}
{{- $e := "prod" -}}
{{- $path := "/website" -}}
PAYLOAD_SECRET={{ with getSecretByName $p $e $path "PAYLOAD_SECRET" }}{{ .Value }}{{ end }}
RESEND_API_KEY={{ with getSecretByName $p $e $path "RESEND_API_KEY" }}{{ .Value }}{{ end }}
CONTACT_TO_EMAIL={{ with getSecretByName $p $e $path "CONTACT_TO_EMAIL" }}{{ .Value }}{{ end }}
CONTACT_FROM_EMAIL={{ with getSecretByName $p $e $path "CONTACT_FROM_EMAIL" }}{{ .Value }}{{ end }}
