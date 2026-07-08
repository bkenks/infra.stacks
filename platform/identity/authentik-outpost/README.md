# authentik-outpost

Standalone [Authentik](https://goauthentik.io) **proxy outpost** — the
forward-auth data-plane for the KTB mesh. A single `ghcr.io/goauthentik/proxy`
container that dials the core Authentik server ([`../authentik`](../authentik/))
**outbound** and serves the forward-auth endpoint on `:9000`.

> **Phase 1 scaffolding — not yet wired.** Renders and lints, but inert until a
> host opts it in via Komodo and the outpost token exists in Infisical. No
> Traefik forward-auth middleware points at it yet.

## Deploy target

Runs on **littlebuddy** (alongside the core Authentik stack). It does not need
inbound access to the control plane — it dials `https://auth.ktbcloud.com`
outbound and holds a long-lived outpost API token. It publishes `9000` on the
host so that **every mesh host's Traefik** forward-auths to it over Tailscale
(`http://<littlebuddy-tailscale-ip>:9000`), keeping one shared SSO session
across the mesh. It is intentionally separate from the core stack so the
data-plane can be restarted/scaled without touching the identity control plane.

## Config

| Var | Value | Notes |
|---|---|---|
| `AUTHENTIK_HOST` | `https://auth.ktbcloud.com` | core server, dialed outbound |
| `AUTHENTIK_INSECURE` | `false` | verify TLS to the core server |
| `AUTHENTIK_TOKEN` | *(secret)* | outpost API token |

## Secrets

`AUTHENTIK_TOKEN` is rendered in RAM by the Infisical agent into
`/dev/shm/authentik-outpost.env` (the parent `compose.yaml` `include.env_file`).
Source: Infisical **infra** project, folder `/authentik-outpost` (registry
`agentServices.'authentik-outpost'`, `type: dump` — the Infisical secret is
named `AUTHENTIK_TOKEN`). The token is issued by the core Authentik when the
`internal-forwardauth` outpost is created (see that stack's
`files/blueprints/internal-forwardauth.yaml`).

## Wire-up follow-ups (Phase 2, not in this PR)

- Create the outpost in core Authentik and copy its API token into Infisical
  `infra:/authentik-outpost` as `AUTHENTIK_TOKEN`.
- Add `authentik-forwardauth@file` middleware to each gated router (via the
  `proxyAddAuth` mixin) pointing at this outpost.
