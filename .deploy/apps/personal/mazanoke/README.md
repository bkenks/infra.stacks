# mazanoke

[Mazanoke](https://github.com/civilblur/mazanoke) — self-hosted image compression tool. Reached at `mazanoke.ktbinternal.com` via Traefik → port 80.

Source of truth: `compose.jsonnet` — don't edit the generated YAML (renders both `compose.yaml` and `compose.stack.yaml`).

## Deploy

Deployed via Komodo. Fully stateless — no secrets, no volumes, no DB.
