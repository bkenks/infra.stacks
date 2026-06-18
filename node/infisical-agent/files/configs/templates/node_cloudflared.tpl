{{/*
  Per-host tunnel token. The secret path is host-specific
  (/hosts/<host>/cloudflared), and the Infisical agent's template engine has NO
  access to the environment — so the host can't be read here directly. Instead
  entrypoint.sh substitutes the AGENT_HOST env var into a writable copy of this
  file before the agent runs (see files/entrypoint.sh). Leave the placeholder
  in $path literal — do NOT hardcode a hostname.
*/ -}}
{{- $p := "86324d9b-3dd7-49d4-b252-69228c5ee0c7" -}}
{{- $e := "prod" -}}
{{- $path := "/hosts/${AGENT_HOST}/cloudflared" -}}
CLOUDFLARE_TUNNEL_TOKEN={{ with getSecretByName $p $e $path "TUNNEL_TOKEN" }}{{ .Value }}{{ end }}
