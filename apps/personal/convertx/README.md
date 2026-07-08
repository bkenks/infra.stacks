# convertx

[ConvertX](https://github.com/C4illin/ConvertX) — self-hosted file conversion tool. Reached at `convertx.ktbinternal.com` via Traefik → port 3000.

Source of truth: `compose.jsonnet` / `compose.stack.jsonnet` — don't edit the generated YAML.

## Deploy

Deployed via Komodo. Infisical `/convertx` (`CONVERTX_JWT_SECRET` → `JWT_SECRET`) → `/dev/shm/convertx.env`. Unpinned (`latest`) — upstream publishes no version tags yet; pin once it does. Data is bind-mounted at `${DOCKER_VOLUMES}/apps/convertx` (no rename needed).
