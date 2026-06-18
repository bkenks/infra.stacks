{{- $p := "12ed25dd-c0d2-4a78-9b10-472fc09fe554" -}}
{{- $e := "prod" -}}
{{- $path := "/frappe" -}}
FRAPPE_DB_ROOT_PASSWORD={{ with getSecretByName $p $e $path "FRAPPE_DB_ROOT_PASSWORD" }}{{ .Value }}{{ end }}
