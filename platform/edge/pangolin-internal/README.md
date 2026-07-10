# pangolin-internal
The `ktbinternal.com` [Pangolin](https://docs.pangolin.net/) edge, on `bill`. Second instance of the shape in `.jsonnet/lib/pangolin.libsonnet`; the first is [`../pangolin`](../pangolin) (`ktbcloud.com`, on `rick`). See that README for how the two relate — disjoint DNS planes, separate `SERVER_SECRET`, `servesAuthentik` gating `shared-edge`.

Source of truth is the `.jsonnet`: `compose.jsonnet` and `files/configs.jsonnet` both apply `pangolin.libsonnet` to `./instance.libsonnet`. Don't edit generated YAML. `files/privateConfig.yml` is a hand-maintained empty placeholder.

## Prerequisites before first deploy
- **Retire `traefik_bill`.** It binds `80`/`443`/`22` on this host (`platform/edge/traefik`), and Gerbil needs `80`/`443`. They cannot coexist. `frappe` currently reaches the world through `traefik_bill` via `shared-proxy`, so it needs re-homing first — Pangolin's bundled Traefik uses only the `http` (Pangolin API) and `file` providers, no Docker provider, so it will not pick up frappe's Traefik labels.
- **Infisical:** create folder `/pangolin-internal` (project **apps**) with `SERVER_SECRET` (`openssl rand -base64 32`) and `EMAIL_SMTP_PASS`. It is already wired into `infisical-agent_bill`'s `AGENT_SERVICES`, alongside the shared `cloudflare__dns-api-token`.
- **`CF_DNS_API_TOKEN`** must carry `Zone:DNS:Edit` on `ktbinternal.com` for the DNS-01 wildcard.
- **Public inbound:** forward `80`, `443`, `443/udp`, `51820/udp`, `21820/udp` from the router to bill (`192.168.30.25`), and point `pangolin.ktbinternal.com` + `*.ktbinternal.com` at the WAN address. Residential IPs drift — expect to want DDNS. Cert issuance itself is DNS-01 and never needs inbound `80`.
- **Firewall:** the `edge` group (`80`, `443`, `51820`, `21820`) in `infra.ansible` has no host members. Add `rick` and `bill`, and add `443/udp` — Gerbil publishes HTTP/3.
- LAN clients still reach the dashboard through the controller Traefik, which routes `pangolin.ktbinternal.com` to `host-bill` (`registry.libsonnet` `controllerServices`). That avoids depending on NAT hairpin.

## IdP
Authentik runs on `rick`, so this instance does **not** join `shared-edge` and does not front `auth.ktbcloud.com`. It uses Authentik as an external OIDC IdP over the public internet at `https://auth.ktbcloud.com`, registered in the Pangolin UI (Server Admin → Identity Providers).

Two consequences worth knowing:
- Authentik is served *through rick's Pangolin Traefik*, so SSO into this instance depends on rick being up. Keep a local admin account here as break-glass.
- The Authentik blueprint needs a second provider + application with distinct `identifiers` (`name`/`slug`) and redirect URI `https://pangolin.ktbinternal.com/api/v1/auth/idp/oidc/callback`. Reusing the existing `pangolin` identifiers overwrites that provider instead of adding one.
