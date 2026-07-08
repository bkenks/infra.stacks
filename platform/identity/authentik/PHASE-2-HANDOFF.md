# Authentik SSO — Phase 2 Handoff

> Phase 1 (scaffolding) merged; Phase 2 is stand-up + wiring. Nothing Authentik-related is deployed yet.

## Repo facts
- Repo: `~/ghq/fj.homektb.com/ktbgroup-self-hosted/infra.stacks`.
- `.jsonnet/render.sh <file>` renders; lefthook re-renders on commit (staged `.libsonnet` re-renders ALL jsonnet); dclint needs pinned image tags.
- Forgejo remote — PRs via `tea`, not gh: `tea pr create --login fj.lilbud.homektb.com --repo ktbgroup-self-hosted/infra.stacks --head <branch> --base main --title "..." --description "$(cat file)"`. Direct pushes to `main` are hook-blocked → feature branch + PR.
- Commit footer: `Claude-Session: <session url>`. "in komodo" = `mcp__komodo__*` MCP tools, not SSH/docker.
- Komodo auto-commit bot periodically rewrites `platform/container-manager/komodo/files/komodo-config-sync.toml` — expect `main` to advance under you.
- Background jobs: isolate in a worktree (`git worktree add -b <b> <repo>/.claude/worktrees/<name> origin/main`); lefthook prunes `.claude/` so worktrees don't break the render sweep.

## Architecture decisions (settled — do not relitigate)
- Two domains: internal **`ktbinternal.com`**, external **`ktbcloud.com`**. `homektb.com` kept, no longer default. `ktbhosting.com` owned, parked.
- Authentik = central IdP, on **rick (VPS)**, public at **`auth.ktbcloud.com`**, bundled Postgres+Redis (NOT shared-postgres — public IdP must not depend on the internal DB over Tailscale).
- Public plane: Pangolin on rick serves `*.ktbcloud.com`. Per-resource auth: Authentik OIDC for apps, raw login for Plex.
- Internal plane: Traefik mesh for `*.ktbinternal.com` + Authentik forward-auth outpost. NO second Pangolin.
- Outpost topology: ONE outpost on **littlebuddy** to start; scale per-host later if latency/HA bites.
- No paid OIDC licenses → Twenty, Docuseal, Infisical get raw login / forward-auth, not native OIDC.
- Break-glass: never put Authentik itself or Pangolin's admin behind Authentik SSO — keep `akadmin` bootstrap creds + a Pangolin-local admin.

## What's already built (PR #21, merged, inert until deployed)
Under `platform/identity/`:
- `authentik/` — `authentik_db` postgres:16-alpine, `authentik_redis` redis:7-alpine, `authentik_server`+`authentik_worker` ghcr.io/goauthentik/server:2026.5.3; joins private net + `shared-edge`; `AUTHENTIK_COOKIE_DOMAIN=ktbcloud.com`. Plus `.env.example`, `files/blueprints/{pangolin-oidc,internal-forwardauth}.yaml` (DRAFTS).
- `authentik-outpost/` — `ghcr.io/goauthentik/proxy:2026.5.3`, `AUTHENTIK_HOST=https://auth.ktbcloud.com`, publishes `:9000`, target littlebuddy.
- `registry.libsonnet`: `sharedNetworks.edge` (`shared-edge`, owner authentik); `agentServices.authentik` (map, project infra, folder `/authentik`); `agentServices.authentik-outpost` (dump, folder `/authentik-outpost`).
- `mixins.libsonnet`: `proxyAddAuth(router,sub,port,domain)` = proxyAdd + `authentik-forwardauth@file` middleware label.
- `komodo-config-sync.toml`: seeds for `template__authentik` + `template__authentik-outpost`. `docker-resource-manager` auto-creates `shared-edge`.

## Phase 2 steps (each independently reversible; keep break-glass throughout)
1. **Cert/token prep.** Widen `CF_DNS_API_TOKEN` to the `ktbcloud.com` zone. Add `ktbcloud.com` as a Pangolin domain in `platform/edge/pangolin/files/config.yml` and `*.ktbcloud.com` to its cert request in `dynamic_config.yml`.
2. **Infisical secrets.** Create project **infra** folder `/authentik` (prod): `AUTHENTIK_SECRET_KEY` (`openssl rand -base64 60`), `PG_PASS` (`openssl rand -base64 36`), `BOOTSTRAP_PASSWORD`, `BOOTSTRAP_TOKEN`, `BOOTSTRAP_EMAIL`. Create `/authentik-outpost` with `AUTHENTIK_TOKEN` (minted AFTER core is up / via blueprint).
3. **Opt hosts in (Komodo).** rick's `infisical-agent` `AGENT_SERVICES` += `authentik`; littlebuddy's += `authentik-outpost`.
4. **Deploy Authentik core on rick** (Komodo stack). Verify `akadmin` login via rick's Tailscale IP:9000 BEFORE exposing publicly.
5. **Expose `auth.ktbcloud.com`.** gerbil joins `shared-edge`; add a **raw** `authentik-router` (NO SSO middleware, or login loop) → `http://authentik_server:9000` in pangolin `dynamic_config.yml`; DNS `auth.ktbcloud.com` → rick, **DNS-only (grey)**. Confirm OIDC discovery loads publicly + cert issues.
6. **Validate blueprints** against running Authentik **2026.5.3** — `!Find`/`!KeyOf` tags, flow slugs, scope mappings, signing key are GUESSES. Fix in `files/blueprints/`. (`internal-forwardauth`'s `cookie_domain` is already `ktbinternal.com`, `external_host` = `auth.ktbcloud.com`.)
7. **Pilot ONE native-OIDC app** (Forgejo or Immich) straight to Authentik before touching Pangolin.
8. **Pangolin → Authentik OIDC.** Add Authentik as external OIDC IdP in Pangolin (Server Admin → Identity Providers); copy Pangolin's redirect URI back into the Authentik provider (Strict). Flip ONE low-risk `*.ktbcloud.com` resource to SSO. Plex stays raw (SSO off).
9. **Internal forward-auth.** Deploy `authentik-outpost` on littlebuddy; add `authentik-forwardauth` middleware + `/outpost.goauthentik.io/` router to `platform/edge/traefik/files/host.yml` (address = littlebuddy tailnet IP `100.114.137.104:9000`); apply `proxyAddAuth` to ONE no-OIDC service (e.g. sonarr). Proxy provider = domain-level, cookie domain `ktbinternal.com`.
10. **Cut services over by tier** (native-OIDC first, forward-auth last): native-OIDC = openproject/immich/paperless/forgejo/gitea/komodo/frappe; forward-auth/raw = *arr stack/convertx/seerr/docuseal/infisical/twenty; raw = Plex; tailnet-only = postgres/databasus/zerobyte/komodo-mcp.

## Follow-ups / debt
- Open PRs: #23 (lefthook `.claude/` prune), #25 (`controller.yaml` generated from registry catalog). #22 domain migration already merged.
- Edge configs → jsonnet-generated: controller.yaml DONE (#25). TODO: `traefik/files/{host,traefik}.yml`, `pangolin/files/{config,dynamic_config,traefik_config,privateConfig}.yml`.
- Authentik bundled Postgres needs a pg_dump/backup job (outside databasus's shared-postgres coverage).

## Key doc URLs
- https://docs.goauthentik.io/install-config/install/docker-compose/
- https://docs.goauthentik.io/add-secure-apps/providers/oauth2
- https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_traefik
- https://docs.pangolin.net/manage/identity-providers/openid-connect
- https://integrations.goauthentik.io/networking/pangolin
