# convertx

[ConvertX](https://github.com/C4illin/ConvertX) — self-hosted file conversion tool. Reached at `convertx.ktbinternal.com` via Traefik → port 3000.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Infisical `/convertx` supplies `JWT_SECRET` through the infisical-secrets provider, stored under that name. Unpinned (`latest`) — upstream publishes no version tags yet; pin once it does. Data is bind-mounted at `${DOCKER_VOLUMES}/apps/convertx` (no rename needed).
