# pangolin
[Pangolin](https://docs.pangolin.net/) — self-hosted tunnel + reverse proxy exposing internal services (incl. raw TCP/UDP) to the public internet without inbound ports on the origin host. Three containers: `pangolin` (control plane/dashboard), `gerbil` (WireGuard tunnel server, owns public `80/443/51820/21820`), `traefik` (HTTP routing + Let's Encrypt).

Source of truth is `stack.pkl` (services + the manifest) and `files/config.pkl` (the shared config shape), which `stack.pkl` applies to the reach domain and renders as the four YAML files under `files/` (`config`, `dynamic_config`, `traefik_config`, `privateConfig`). Don't edit generated YAML.

## Single instance — the VPS edge on rick (`pangolin.ktbcloud.com`)
**The single knob is `host`** (`= "pangolin.\(urlDomain)"` in `files/config.pkl`, passed `ktbcloud` by `stack.pkl`) — the domain the instance is reached at. It drives `dashboard_url`, gerbil's `base_endpoint`, the CORS origin, and every dashboard `Host()` rule. The instance declares both DNS planes and holds both wildcard certs.

## Deploy
- Dedicated edge host. Gerbil binds `80`/`443` itself (`network_mode: service:gerbil`), so **do not** also deploy `platform/edge/traefik` on this host.
- QUIRK: services are keyed by role (`app`, `tunnel`, `proxy`, `seeder`) but `container_name`s (`pangolin`, `gerbil`, `traefik`) are literal overrides — Gerbil's startup flags and `files/config.pkl` hardcode these hostnames; renaming any breaks service discovery. Komodo's `ignore_services` for this stack must name `seeder` (the one-shot init).
- Certs via Cloudflare DNS-01 ACME (same as `platform/edge/traefik`). `next-router` requests both the `*.ktbinternal.com` and `*.ktbcloud.com` wildcards; every other router reuses them via SNI with `certResolver: cloudflare`. Each host's `CF_DNS_API_TOKEN` must cover both zones.
- Secrets: two infisical-secrets provider services, one per bundle. `secrets` reads Infisical `/pangolin` (project **apps**) for `SERVER_SECRET` (`openssl rand -base64 32`) and `EMAIL_SMTP_PASS`; `secrets-traefik` reads `/traefik` for `CF_DNS_API_TOKEN`, the same DNS-01 token anything else doing DNS-01 uses — don't duplicate it into this stack's own bundle. One provider service serves one path, which is why there are two.
- QUIRK: `files/config.pkl` omits `server.secret`/`email.smtp_pass` entirely (not blanked) — Pangolin's config loader only applies the env override when the key is *absent*; `secret: ""` counts as "defined" and fails the `>=8 char` validation before the env var is read.
- Storage: everything under one host dir, `/srv/docker/bind-mounts/pangolin/config` (no named volumes). The `seeder` container creates the tree/permissions and downloads the GeoLite2 DBs on first run only; Pangolin's own runtime state (db, Gerbil's WireGuard key) also lives there and persists across redeploys.
