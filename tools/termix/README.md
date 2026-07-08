# termix

Termix — self-hosted web SSH/terminal + server-management UI. Reached at **https://termix.ktbinternal.com** (port 8080). Ships with `guacd` (Guacamole proxy) as an internal-only sidecar for remote-desktop connections.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` — don't edit the generated YAML.

## Deploy

Deployed via Komodo. No secrets — only config is the literal `PORT` in `compose.stack.jsonnet`. Image versions pinned there (`appVersion`, `guacdVersion`).

First deploy: rename the old implicit volume:
```bash
.scripts/rename-volume.sh termix_termix-data termix-data
```

Validate locally: `tests/render_compose.sh` (any `docker compose config` flag passes through).
