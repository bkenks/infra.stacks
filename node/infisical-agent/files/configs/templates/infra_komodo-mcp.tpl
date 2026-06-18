{{- $p := "86324d9b-3dd7-49d4-b252-69228c5ee0c7" -}}
{{- $e := "prod" -}}
{{- $path := "/komodo-mcp" -}}
KOMODO_API_KEY={{ with getSecretByName $p $e $path "KOMODO_API_KEY" }}{{ .Value }}{{ end }}
KOMODO_API_SECRET={{ with getSecretByName $p $e $path "KOMODO_API_SECRET" }}{{ .Value }}{{ end }}
KOMODO_MCP_BASICAUTH_USERS={{ with getSecretByName $p $e $path "KOMODO_MCP_BASICAUTH_USERS" }}{{ .Value }}{{ end }}