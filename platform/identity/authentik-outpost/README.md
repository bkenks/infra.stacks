# authentik-outpost
Standalone [Authentik](https://goauthentik.io) **proxy outpost** — the forward-auth data-plane for the KTB mesh. Single `ghcr.io/goauthentik/proxy` container dialing the core Authentik server ([`../authentik`](../authentik/)) outbound, serving forward-auth on `:9000`.

> Phase 1 scaffolding — not yet wired. Inert until a host opts it in via Komodo and the outpost token exists in Infisical.

## Deploy

- Target: **littlebuddy** (core Authentik runs on rick). Publishes `9000` so every mesh host's Traefik can forward-auth to it over Tailscale, keeping one shared SSO session across the mesh.
- Secrets: Infisical **infra** `/authentik-outpost` (`type: dump`, secret `AUTHENTIK_TOKEN`) → `/dev/shm/authentik-outpost.env`. Token is issued by core Authentik when the `internal-forwardauth` outpost is created.

## Wire-up follow-ups (Phase 2)

- Create the outpost in core Authentik, copy its token into Infisical `infra:/authentik-outpost`.
- Add `authentik-forwardauth@file` middleware to each gated router via the `proxyAddAuth` mixin.
