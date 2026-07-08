# Authentik SSO — Phase 2 Handoff

> Written to resume cold after a context clear. Phase 1 (scaffolding) is done & merged; Phase 2 is the actual stand-up + wiring. Nothing Authentik-related is deployed yet.

## Repo / operational facts (read first)
- Repo: `~/ghq/fj.homektb.com/ktbgroup-self-hosted/infra.stacks` (**note: `fj.homektb.com`, not `fj.lilbud.*`** — that path was stale in earlier context).
- jsonnet→yaml compose stacks via **Komodo**. `.jsonnet/render.sh <file>` renders; **lefthook** re-renders on commit (a staged `.libsonnet` re-renders ALL jsonnet). dclint needs pinned image tags.
- Forgejo remote. PRs via **`tea`**, not gh: `tea pr create --login fj.lilbud.homektb.com --repo ktbgroup-self-hosted/infra.stacks --head <branch> --base main --title "..." --description "$(cat file)"`.
- Direct pushes to `main` are hook-blocked → always feature branch + PR.
- Commit footer: `Claude-Session: <session url>`. "in komodo" = the `mcp__komodo__*` MCP tools, not SSH/docker.
- A **Komodo auto-commit bot** periodically writes `platform/container-manager/komodo/files/komodo-config-sync.toml` → expect `main` to advance under you.
- Background jobs: isolate edits in a worktree (`git worktree add -b <b> <repo>/.claude/worktrees/<name> origin/main`; cd in). lefthook now prunes `.claude/` (PR #23) so worktrees don't break the render sweep.

## Architecture decisions (settled — do not relitigate)
- **Two domains / two planes.** Internal zone = **`ktbinternal.com`** (registry `domains.ktbinternal`; migrated from homektb.com). External zone = **`ktbcloud.com`**. `homektb.com` kept as a named domain but no longer default. `ktbhosting.com` owned, parked.
- **Authentik = central IdP.** Runs on **rick (the VPS)**, public at **`auth.ktbcloud.com`**. Bundled Postgres + Redis inside the stack (NOT shared-postgres — that's on littlebuddy; the public IdP must not depend on the internal DB over Tailscale).
- **Public plane:** Pangolin on rick serves `*.ktbcloud.com`. Per-resource auth: Authentik OIDC for your apps, **raw** (app's own login) for Plex.
- **Internal plane:** keep the **Traefik mesh** for `*.ktbinternal.com` + an **Authentik forward-auth outpost** for SSO. **NO second Pangolin.**
- **Why this shape (verified against Pangolin docs):** Pangolin's built-in IdP is instance-local (can't federate across instances, can't be an OIDC provider for other apps); Pangolin public HTTP resources always hairpin through the central server. So identity is externalized to Authentik, and internal routing stays on the hairpin-free mesh.
- **Outpost topology:** ONE outpost on **littlebuddy** to start (other hosts do a one-hop tailnet call). Scale to per-host later if latency/HA bites.
- **No paid OIDC licenses** → Twenty, Docuseal, Infisical get raw login / forward-auth, not native OIDC.
- **Break-glass:** never put Authentik itself or Pangolin's admin behind Authentik SSO. Keep the `akadmin` bootstrap creds + a Pangolin-local admin.

## What's already built (PR #21, MERGED, inert until deployed)
Under `platform/identity/`:
- `authentik/` — `compose.jsonnet` + `compose.stack.jsonnet` (services: `authentik_db` postgres:16-alpine, `authentik_redis` redis:7-alpine, `authentik_server` + `authentik_worker` ghcr.io/goauthentik/server:2026.5.3; `shm_size: 512mb`; joins its private net + **`shared-edge`**; server/worker share a base; `AUTHENTIK_COOKIE_DOMAIN=ktbcloud.com`). Plus `README.md`, `.env.example`, `files/blueprints/{pangolin-oidc,internal-forwardauth}.yaml` (DRAFTS).
- `authentik-outpost/` — `ghcr.io/goauthentik/proxy:2026.5.3`, `AUTHENTIK_HOST=https://auth.ktbcloud.com`, `AUTHENTIK_TOKEN=${...}`, publishes `:9000`. Deploy target littlebuddy.
- `registry.libsonnet`: `sharedNetworks.edge` (`shared-edge`, owner authentik); `agentServices.authentik` (map type, project infra, folder `/authentik`, keys AUTHENTIK_SECRET_KEY/PG_PASS→both PG vars/BOOTSTRAP_*), `agentServices.authentik-outpost` (dump, folder `/authentik-outpost`).
- `mixins.libsonnet`: `proxyAddAuth(router,sub,port,domain)` = proxyAdd + `authentik-forwardauth@file` middleware label.
- `komodo-config-sync.toml`: server-less `template__authentik` + `template__authentik-outpost` seeds.
- `docker-resource-manager` auto-creates `shared-edge` (it iterates `reg.sharedNetworks`).

## Phase 2 steps (each independently reversible; keep break-glass throughout)
1. **Cert/token prep.** Widen `CF_DNS_API_TOKEN` to the `ktbcloud.com` zone. Add `ktbcloud.com` as a Pangolin domain in `platform/edge/pangolin/files/config.yml` and `*.ktbcloud.com` to its cert request in `dynamic_config.yml`.
2. **Infisical secrets.** Create project **infra** folder `/authentik` (prod): `AUTHENTIK_SECRET_KEY` (`openssl rand -base64 60`), `PG_PASS` (`openssl rand -base64 36`), `BOOTSTRAP_PASSWORD`, `BOOTSTRAP_TOKEN`, `BOOTSTRAP_EMAIL`. Create `/authentik-outpost` with `AUTHENTIK_TOKEN` (minted AFTER core is up / via blueprint).
3. **Opt hosts in (Komodo).** rick's `infisical-agent` `AGENT_SERVICES` += `authentik`; littlebuddy's += `authentik-outpost`.
4. **Deploy Authentik core on rick** (Komodo stack). Verify `akadmin` login via rick's Tailscale IP:9000 BEFORE exposing publicly.
5. **Expose `auth.ktbcloud.com`.** gerbil joins `shared-edge`; add a **raw** `authentik-router` (NO badger/SSO middleware, or you get a login loop) → `http://authentik_server:9000` in pangolin `dynamic_config.yml`; DNS `auth.ktbcloud.com` → rick, **DNS-only (grey)**. Confirm the OIDC discovery URL loads publicly + cert issues.
6. **Validate blueprints** against running Authentik **2026.5.3** — the `!Find`/`!KeyOf` tags, flow slugs (`default-provider-authorization-implicit-consent` etc.), scope mappings, signing key are GUESSES. Fix in `files/blueprints/`. (Internal-forwardauth `cookie_domain` is already `ktbinternal.com`, `external_host` = `auth.ktbcloud.com`.)
7. **Pilot ONE native-OIDC app** (Forgejo or Immich) straight to Authentik. Validate end-to-end before touching Pangolin.
8. **Pangolin → Authentik OIDC.** Add Authentik as an external OIDC IdP in Pangolin (Server Admin → Identity Providers); copy Pangolin's generated redirect URI back into the Authentik provider (Strict). Flip ONE low-risk `*.ktbcloud.com` resource to SSO. Plex resource = SSO OFF (raw).
9. **Internal forward-auth.** Deploy `authentik-outpost` on littlebuddy; add the `authentik-forwardauth` forwardAuth middleware + `/outpost.goauthentik.io/` router to `platform/edge/traefik/files/host.yml` (address = littlebuddy tailnet IP:9000, `100.114.137.104`); apply `proxyAddAuth` to ONE no-OIDC service (e.g. sonarr). Proxy provider = domain-level, cookie domain `ktbinternal.com`.
10. **Cut services over by tier** (native-OIDC first, forward-auth last). Tiers: native-OIDC = openproject/immich/paperless/forgejo/gitea/komodo/frappe; forward-auth/raw = the *arr stack, convertx, seerr, docuseal, infisical, twenty; raw = Plex; tailnet-only = postgres/databasus/zerobyte/komodo-mcp.

## Follow-ups / debt (separate track, not blocking Phase 2)
- **Open PRs to merge:** #23 (lefthook `.claude/` prune), #25 (`controller.yml` → generated from registry catalog — validated structurally identical). #22 domain migration already merged.
- **Edge configs → jsonnet-generated** (single-source-of-truth push): controller.yml DONE (#25). TODO same treatment for `traefik/files/host.yml`, `traefik/files/traefik.yml`, `pangolin/files/{config,dynamic_config,traefik_config,privateConfig}.yml`. See memory `infra-stacks-domain-single-source`.
- Authentik bundled Postgres needs a pg_dump/backup job (outside databasus's shared-postgres coverage).

## Key doc URLs
- Authentik compose: https://docs.goauthentik.io/install-config/install/docker-compose/
- Authentik OAuth2 provider: https://docs.goauthentik.io/add-secure-apps/providers/oauth2
- Authentik Traefik forward-auth outpost: https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_traefik
- Pangolin OIDC IdP: https://docs.pangolin.net/manage/identity-providers/openid-connect
- Pangolin ↔ Authentik integration: https://integrations.goauthentik.io/networking/pangolin
