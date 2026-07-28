# stirling-pdf

[Stirling PDF](https://www.stirlingpdf.com/) — self-hosted PDF toolkit. Reached at `stirling-pdf.ktbinternal.com` via Traefik → port 8080.

Source of truth: `stack.jsonnet` — don't edit the generated YAML (renders both `stack.compose.yaml` and `stack.services.yaml`).

## Deploy

Deployed via Komodo. No secrets — login is enabled and Stirling seeds a default admin (`admin`/`stirling`) on first boot; change it immediately in Settings → Account. To seed real credentials instead, set `SECURITY_INITIALLOGIN_USERNAME`/`_PASSWORD` and add the password to Infisical (mirror how other stacks pull secrets in).
