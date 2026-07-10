# pangolin
[Pangolin](https://docs.pangolin.net/) — self-hosted tunnel + reverse proxy exposing internal services (incl. raw TCP/UDP) to the public internet without inbound ports on the origin host. Three containers: `pangolin` (control plane/dashboard), `gerbil` (WireGuard tunnel server, owns public `80/443/51820/21820`), `traefik` (HTTP routing + Let's Encrypt).

**This is the `ktbcloud.com` edge, on `rick` (the VPS).** Its sibling is [`../pangolin-internal`](../pangolin-internal) (`ktbinternal.com`, on `bill`). Both are instances of the same shape — `.jsonnet/lib/pangolin.libsonnet` — differing only by `./instance.libsonnet`.

Source of truth is the `.jsonnet`: `compose.jsonnet` (renders `compose.yaml` + `compose.stack.yaml`) and `files/configs.jsonnet` (renders `config.yaml`/`dynamic_config.yaml`/`traefik_config.yaml`) both apply `pangolin.libsonnet` to `instance.libsonnet`. Don't edit generated YAML. `files/privateConfig.yml` is a hand-maintained empty placeholder, not generated.

## Two instances
- **One DNS plane each, and they must be disjoint.** An instance requests its zone's wildcard cert and answers for every `Host()` under it. Give both the same `baseDomain` and they race on the DNS-01 challenge and publish competing routers. `config.yaml` therefore declares a single `domain1`.
- **Separate `SERVER_SECRET`.** Each instance has its own Infisical folder (`/pangolin` here, `/pangolin-internal` there). A shared secret would let either instance mint session tokens the other accepts.
- **`servesAuthentik` gates `shared-edge`.** That network is external and owned by the `authentik` stack. Only the instance colocated with Authentik joins it (and publishes the raw `auth.<baseDomain>` router). A host without Authentik has nothing to create the network, and Compose refuses to start against a missing external one.
- `dataDir` is pinned to `pangolin` here rather than defaulting to the project name — rick already holds live state there (Gerbil's WireGuard key, Pangolin's db, `acme.json`) and renaming the path orphans all three.

## Deploy
- Dedicated edge host. Gerbil binds `80`/`443` itself (`network_mode: service:gerbil`), so **do not** also deploy `platform/edge/traefik` on this host.
- QUIRK: service keys/`container_name`s (`pangolin`, `gerbil`, `traefik`) are literal, not run through `lib.compose.names()` — Gerbil's startup flags and `pangolin.libsonnet`'s backend URLs hardcode these hostnames; renaming any breaks service discovery. Safe across instances because no two share a host.
- Certs via Cloudflare DNS-01 ACME (same as `platform/edge/traefik`). `next-router` requests the `*.ktbcloud.com` wildcard once; every other router (including ones Pangolin adds dynamically) reuses it via SNI with `certResolver: cloudflare`. `CF_DNS_API_TOKEN` must be scoped to this instance's zone.
- Secrets: Infisical `/pangolin` (project **apps**) → `/dev/shm/pangolin.env`: `SERVER_SECRET` (`openssl rand -base64 32`), `EMAIL_SMTP_PASS`. Also needs the shared `/traefik` secret (project **infra**) `CF_DNS_API_TOKEN` → `/dev/shm/cloudflare__dns-api-token.env` — same one `platform/edge/traefik` uses, don't duplicate it. Add **both** `pangolin` and `cloudflare__dns-api-token` to this host's `infisical-agent` `AGENT_SERVICES`.
- QUIRK: `config.yaml` omits `server.secret`/`email.smtp_pass` entirely (not blanked) — Pangolin's config loader only applies the env override when the key is *absent*; `secret: ""` counts as "defined" and fails the `>=8 char` validation before the env var is read.
- Storage: everything under one host dir, `/srv/docker/bind-mounts/pangolin/config` (no named volumes). The `init` container creates the tree/permissions and downloads the GeoLite2 DBs on first run only; Pangolin's own runtime state (db, Gerbil's WireGuard key) also lives there and persists across redeploys.
- IdP: Authentik, registered in the Pangolin UI (Server Admin → Identity Providers), not in `config.yml` — Pangolin keeps IdP config in its database. Each instance needs its own Authentik OAuth2 provider + application with distinct `identifiers`, since a reused `name`/`slug` overwrites rather than adds.
