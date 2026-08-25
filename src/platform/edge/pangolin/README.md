# pangolin
[Pangolin](https://docs.pangolin.net/) — self-hosted tunnel + reverse proxy exposing internal services (incl. raw TCP/UDP) to the public internet without inbound ports on the origin host. Three containers: `pangolin` (control plane/dashboard), `gerbil` (WireGuard tunnel server, owns public `80/443/51820/21820`), `traefik` (HTTP routing + Let's Encrypt).

Source of truth is the `.jsonnet` — `stack.jsonnet` (names + the manifest), and `files/configs.jsonnet`, which applies `files/config.libsonnet` (the shared config shape) to the reach domain and renders the four YAML files its keys name (`config`, `dynamic_config`, `traefik_config`, `privateConfig`). Don't edit generated YAML.

## Single instance — the VPS edge on rick (`pangolin.ktbcloud.com`)
**The single knob is `host`** (`= 'pangolin.' + urlDomain` in `files/config.libsonnet`, passed `ktbcloud` by `files/configs.jsonnet`) — the domain the instance is reached at. It drives `dashboard_url`, gerbil's `base_endpoint`, the CORS origin, and every dashboard `Host()` rule. The instance declares both DNS planes and holds both wildcard certs.

## Deploy
- Dedicated edge host. Gerbil binds `80`/`443` itself (`network_mode: service:gerbil`), so **do not** also deploy `platform/edge/traefik` on this host.
- QUIRK: service keys/`container_name`s (`pangolin`, `gerbil`, `traefik`) are literal, not run through `lib.compose.names()` — Gerbil's startup flags and `files/config.libsonnet` hardcode these hostnames; renaming any breaks service discovery.
- Certs via Cloudflare DNS-01 ACME (same as `platform/edge/traefik`). `next-router` requests both the `*.ktbinternal.com` and `*.ktbcloud.com` wildcards; every other router reuses them via SNI with `certResolver: cloudflare`. Each host's `CF_DNS_API_TOKEN` must cover both zones.
- Secrets: Infisical `/pangolin` (project **apps**) → `/dev/shm/pangolin.env`: `SERVER_SECRET` (`openssl rand -base64 32`), `EMAIL_SMTP_PASS`. Also needs the shared `/traefik` secret (project **infra**) `CF_DNS_API_TOKEN` → `/dev/shm/cloudflare__dns-api-token.env` — same one `platform/edge/traefik` uses, don't duplicate it. Add **both** `pangolin` and `cloudflare__dns-api-token` to this host's `infisical-agent` `AGENT_SERVICES`.
- QUIRK: `files/config.libsonnet` omits `server.secret`/`email.smtp_pass` entirely (not blanked) — Pangolin's config loader only applies the env override when the key is *absent*; `secret: ""` counts as "defined" and fails the `>=8 char` validation before the env var is read.
- Storage: everything under one host dir, `/srv/docker/bind-mounts/pangolin/config` (no named volumes). The `init` container creates the tree/permissions and downloads the GeoLite2 DBs on first run only; Pangolin's own runtime state (db, Gerbil's WireGuard key) also lives there and persists across redeploys.
