# authentik
Self-hosted SSO / identity provider for the KTB mesh. Public UI at `https://auth.ktbcloud.com`. Core stack (server + worker + Postgres + Redis); the forward-auth data-plane runs separately as [`platform/identity/authentik-outpost`](../authentik-outpost/).

> Phase 1 scaffolding — not yet wired. Inert until a host opts in via Komodo. Blueprints under `files/blueprints/` are **drafts** — their `!Find`/`!KeyOf` tags and flow slugs need validation against the running Authentik version at wire-up.

## Deploy

- Target: **rick (VPS)**. Owns the `shared-edge` network — Pangolin edge Traefik joins it to reach `authentik_server:9000` once wired. Does not join `shared-proxy`.
- Secrets: Infisical **infra** `/authentik` (`type: map`) → `/dev/shm/authentik.env`. See [`.env.example`](./.env.example). Keys: `AUTHENTIK_SECRET_KEY`, `PG_PASS` (mapped to both `AUTHENTIK_POSTGRESQL__PASSWORD` and `POSTGRES_PASSWORD`), `BOOTSTRAP_PASSWORD`, `BOOTSTRAP_TOKEN`, `BOOTSTRAP_EMAIL`.
- `files/blueprints/{pangolin-oidc,internal-forwardauth}.yaml` bind-mounted read-only at `/blueprints/ktb` — drafts, validate before use.

## Wire-up follow-ups (Phase 2)

- Add the `auth.ktbcloud.com` route on the Pangolin edge Traefik → `authentik_server:9000`.
- Read back the generated OIDC client id/secret into Pangolin's config.
- Deploy `authentik-outpost` with the outpost token; add `authentik-forwardauth@file` to each gated router via `proxyAddAuth`.
