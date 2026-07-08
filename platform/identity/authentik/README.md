# authentik

Self-hosted SSO / identity provider for the KTB mesh. Public UI at
`https://auth.ktbcloud.com`. This is the **core** Authentik stack (server +
worker + Postgres + Redis); the forward-auth data-plane runs separately as
[`platform/identity/authentik-outpost`](../authentik-outpost/).

> **Phase 1 scaffolding — not yet wired.** This stack renders and lints but is
> inert until a host opts it in via Komodo. No Pangolin/Traefik routes point at
> it yet, and the blueprints under `files/blueprints/` are **drafts** (their
> `!Find`/`!KeyOf` tags and flow slugs need validation against the running
> Authentik version at wire-up).

## Deploy target

The core identity host — **rick (the VPS)**. It's the public IdP at
`auth.ktbcloud.com`. It owns the `shared-edge` network (registry
`sharedNetworks.edge`); the Pangolin edge stack's Traefik joins that network to
reach `authentik_server:9000` for OIDC / forward-auth once wired. This stack
does **not** join `shared-proxy`. (The forward-auth outpost runs separately on
littlebuddy — see [`../authentik-outpost/`](../authentik-outpost/).)

## Services

| Service | Image | Role |
|---|---|---|
| `authentik_db` | `postgres:16-alpine` | Postgres 16 (named volume `authentik_database`) |
| `authentik_redis` | `redis:7-alpine` | cache / task broker (`--save 60 1`) |
| `authentik_server` | `ghcr.io/goauthentik/server:2026.5.3` | HTTP/OIDC front, publishes `9000` |
| `authentik_worker` | `ghcr.io/goauthentik/server:2026.5.3` | migrations, blueprints, outpost mgmt (root + docker.sock) |

`server` and `worker` share one image and one env base; per-service keys in
`compose.stack.jsonnet` override command / ports / user / networks. Env var
names and the volume layout were verified against the upstream reference at
<https://docs.goauthentik.io/install-config/install/docker-compose/>.

## Secrets

Rendered in RAM by the Infisical agent into `/dev/shm/authentik.env` (the parent
`compose.yaml` `include.env_file`). Source: Infisical **infra** project, folder
`/authentik` (registry `agentServices.authentik`, `type: map`). See
[`.env.example`](./.env.example) for the key mapping. Required Infisical keys:

- `AUTHENTIK_SECRET_KEY` — Django secret key
- `PG_PASS` — Postgres password (mapped to both `AUTHENTIK_POSTGRESQL__PASSWORD` and `POSTGRES_PASSWORD`)
- `BOOTSTRAP_PASSWORD` — initial `akadmin` password
- `BOOTSTRAP_TOKEN` — initial API token (used to provision the outpost)
- `BOOTSTRAP_EMAIL` — initial `akadmin` email

## Blueprints (drafts)

`files/blueprints/` is bind-mounted read-only at `/blueprints/ktb`:

- `pangolin-oidc.yaml` — OAuth2/OIDC provider + `pangolin` application.
- `internal-forwardauth.yaml` — proxy provider (forward-auth) + application +
  outpost binding, cookie domain `ktbinternal.com`.

Both carry a top-of-file warning: their exact YAML tags and flow slugs are
drafts and must be validated against the running Authentik version before use.

## Wire-up follow-ups (Phase 2, not in this PR)

- Add the `auth.ktbcloud.com` route on the Pangolin edge Traefik → `authentik_server:9000`.
- Read back the generated OIDC client id/secret into Pangolin's config.
- Deploy `authentik-outpost` with the outpost token and add
  `authentik-forwardauth@file` to each gated router (via the `proxyAddAuth` mixin).
