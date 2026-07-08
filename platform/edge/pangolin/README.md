# pangolin

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

[Pangolin](https://docs.pangolin.net/) — self-hosted tunnel + reverse proxy for exposing internal services (including raw TCP/UDP, e.g. game servers) to the public internet without opening inbound ports on the origin host. Three containers: `pangolin` (control plane/dashboard), `gerbil` (WireGuard tunnel server — owns the public `80/443/51820/21820` ports on this host), `traefik` (HTTP routing + Let's Encrypt for this edge).

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml`, and `files/{config,dynamic_config,traefik_config}.jsonnet` compile to the matching `.yaml` — do not edit any generated YAML directly. Re-render with `.jsonnet/render.py <source>.jsonnet` (lefthook does it automatically at commit time). `files/privateConfig.yml` is a hand-maintained empty placeholder, not generated.

### Deploy target

This is a **dedicated edge host stack** (the VPS acting as Pangolin's exit node), not deployed to every host like `platform/edge/traefik`. Gerbil binds `80`/`443` itself (`network_mode: service:gerbil` on the `traefik` service), so **do not deploy `platform/edge/traefik` on the same host** — they'll fight over the same ports.

### Naming deviation

Service keys and `container_name`s (`pangolin`, `gerbil`, `traefik`) are literal strings, not run through `lib.compose.names()`. Gerbil's own startup flags (`--remoteConfig=http://pangolin:3001/...`, `--reachableAt=http://gerbil:3004`) and `files/dynamic_config.jsonnet`'s backend URLs hardcode these hostnames, and Traefik's `network_mode: service:gerbil` requires Gerbil's compose key to be exactly `gerbil` — renaming any of them breaks service discovery. This is the one stack in the repo that deviates from the `<stack>_<role>` convention.

### Certificates

Traefik gets its certs via Cloudflare DNS-01 ACME — same mechanism as `platform/edge/traefik`, not HTTP-01. `files/dynamic_config.jsonnet`'s `next-router` requests the `*.ktbinternal.com` wildcard once (`tls.domains`); every other router — including ones Pangolin adds dynamically for new Resources — reuses it via SNI with just `certResolver: cloudflare`. See `files/traefik_config.jsonnet`'s `certificatesResolvers.cloudflare` block.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/pangolin` folder, project **apps** (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.pangolin`):
  - `SERVER_SECRET` — Pangolin's session/crypto secret (`server.secret` in `files/config.jsonnet`, overridden via env — see [config-file docs](https://docs.pangolin.net/)). Generate with `openssl rand -base64 32`.
  - `EMAIL_SMTP_PASS` — the Resend SMTP API key (`email.smtp_pass` in `files/config.jsonnet`).
- See `.env.example` for the exact keys expected.
- The agent renders these to `/dev/shm/pangolin.env` on the same host; `compose.jsonnet`'s `include.env_file` pulls it in.
- `CF_DNS_API_TOKEN` (Traefik's DNS-01 challenge) is **not** stored under `/pangolin` — it's the same shared secret `platform/edge/traefik` uses (Infisical folder `/traefik`, project **infra**, registry key `agentServices.'cloudflare__dns-api-token'`), rendered to `/dev/shm/cloudflare__dns-api-token.env` and included alongside `pangolin.env`. Nothing to duplicate in Infisical — it already exists.
- Add **both** `pangolin` and `cloudflare__dns-api-token` to this host's `infisical-agent` `AGENT_SERVICES` env var in Komodo so it renders both fragments (`platform/secrets-manager/infisical-agent/templates/{pangolin,cloudflare__dns-api-token}.yaml`).

`files/config.jsonnet` **omits** `server.secret` and `email.smtp_pass` entirely (not blanked — Pangolin's config loader only applies the `SERVER_SECRET`/`EMAIL_SMTP_PASS` env overrides when the key is *absent*; leaving it as `secret: ""` counts as "defined" and fails validation, `>=8 characters`, before the env var is ever consulted).

### Storage

Everything lives under one shared host directory, `/srv/docker/bind-mounts/pangolin/config` (no named volumes — same style as `apps/media/stream`), because Pangolin/Gerbil/Traefik read and write into this tree by upstream design:

- `init` (busybox, one-shot) creates the directory tree and permissions before the real services start (`traefik/logs/`, `letsencrypt/`, `letsencrypt/acme.json` at `600`), and downloads `GeoLite2-Country.mmdb`/`GeoLite2-ASN.mmdb` on first run only (skipped once they already exist on the host). Source is the same community redistribution mirror Pangolin's own installer uses (`github.com/GitSquared/node-geolite2-redist` — not MaxMind directly, so no license key/account needed). It does **not** provision the rest of the config content.
- Config is jsonnet-generated (`files/config.jsonnet`, `files/traefik_config.jsonnet`, `files/dynamic_config.jsonnet` → matching `.yaml`) plus the hand-maintained empty `files/privateConfig.yml`; all git-tracked in this repo and bind-mounted read-only over the writable host dir.
- Pangolin's own runtime state (its db, Gerbil's WireGuard key) also lives in this same tree and persists there across redeploys.

### Compose Commands

*Start Stack (local/standalone testing only — in prod deploy via Komodo):*
```bash
docker compose up -d
```
