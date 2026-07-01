# stirling-pdf

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Stirling PDF](https://www.stirlingpdf.com/) — self-hosted PDF toolkit. Reached at `stirling-pdf.homektb.com` via Traefik, forwarding to the container's port `8080`.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Secrets

No secrets today — `compose.jsonnet` has no `include.env_file` and there's no `agentServices` registry entry for this stack.

Login is enabled (`SECURITY_ENABLELOGIN=true`) and Stirling seeds a default admin (`admin`/`stirling`) on first boot — change it immediately in Settings → Account. The user database lives in the persisted `/configs` bind mount.

To seed admin credentials instead of the default, set `SECURITY_INITIALLOGIN_USERNAME` / `SECURITY_INITIALLOGIN_PASSWORD` in `compose.stack.jsonnet`'s `environment:` block. Treat the password as a secret: add it to Infisical, add an `agentServices` registry entry for this stack, and reference it as `${VAR:?err}` — mirroring how `docuseal`/other stacks pull secrets in.

Non-secret config (language picker, etc.) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

### Hostname (new pick)

The old stack had no pre-existing hostname — it was reached via a bare published port (`20290`). This migration picks `stirling-pdf.homektb.com` as the new Traefik hostname; there was no prior convention to preserve here.

### Reachability change

This stack previously published directly to the host (`20290:8080`, i.e. `<host>:20290`). The jsonnet version drops the host port publish in favor of `expose:` + Traefik — it's now reached at `https://stirling-pdf.homektb.com` only. Any bookmark/reference to the old `host:20290` URL needs to move to the new hostname.

### Staging dropped

This migration converts **production only** (the old stack had no staging overlay to begin with — just a single `DOCK_ENV`-templated `compose.yaml`). If staging is needed later, add it as a jsonnet parameter rather than a separate old-style overlay file.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
