# Authentik — Deploy Runbook (Phase 2)

Ordered, live stand-up of the Authentik IdP. Each step is independently
reversible. **Keep break-glass throughout:** never put Authentik itself or
Pangolin's admin behind Authentik SSO — keep the `akadmin` bootstrap creds and a
Pangolin-local admin working.

The **repo/config prep** for the public plane is staged in **PR #26**
(`feat/authentik-edge-prep`, inert): `pangolin/files/config.yml` registers
`ktbcloud.com`, `dynamic_config.yml` adds the raw `auth.ktbcloud.com` router +
`*.ktbcloud.com` wildcard cert, and `gerbil` joins `shared-edge`. Everything
below is the live wiring that PR can't do. **Hold the PR #26 merge until step 4
is verified** — otherwise the router points at a backend that doesn't exist yet.

Conventions: "in Komodo" = the `mcp__komodo__*` MCP tools, never SSH/`docker`.
Secrets live in Infisical and are rendered to `/dev/shm` by each host's
`infisical-agent`.

---

## 1. Cert / token prep
- [ ] **Widen `CF_DNS_API_TOKEN`** to include the **`ktbcloud.com`** zone
      (currently scoped to `ktbinternal.com`: Zone:DNS:Edit + Zone:Read). Without
      this the `*.ktbcloud.com` wildcard cert can't issue via DNS-01. Shared
      token — used by both `platform/edge/pangolin` and `platform/edge/traefik`.
- [x] Add `ktbcloud.com` as a Pangolin domain + `*.ktbcloud.com` to the cert
      request — **done in PR #26** (`config.yml` `domain2`, `dynamic_config.yml`
      `authentik-router`).

## 2. Infisical secrets
Project **infra**, prod environment.
- [ ] Folder **`/authentik`**:
  - `AUTHENTIK_SECRET_KEY` — `openssl rand -base64 60`
  - `PG_PASS` — `openssl rand -base64 36`
  - `BOOTSTRAP_PASSWORD`
  - `BOOTSTRAP_TOKEN`
  - `BOOTSTRAP_EMAIL`
- [ ] Folder **`/authentik-outpost`**:
  - `AUTHENTIK_TOKEN` — mint **after** core is up (step 6, via blueprint /
    outpost token in the Authentik UI), then fill this in.

The `agentServices` mapping (which secret → which env var) is already defined in
`registry.libsonnet`: `authentik` maps `AUTHENTIK_SECRET_KEY` + `PG_PASS` (→ both
PG vars and `BOOTSTRAP_*`); `authentik-outpost` dumps `/authentik-outpost`.

## 3. Opt hosts into the agents (Komodo)
- [ ] rick's `infisical-agent` `AGENT_SERVICES` **+= `authentik`**
- [ ] littlebuddy's `infisical-agent` `AGENT_SERVICES` **+= `authentik-outpost`**

Confirm each agent renders its env files to `/dev/shm` after the change.

## 4. Deploy Authentik core on rick (Komodo)
- [ ] Deploy the **`authentik`** stack (`platform/identity/authentik`) to **rick**.
      Brings up `authentik_db` (postgres:16), `authentik_redis`,
      `authentik_server` + `authentik_worker` (`:2026.5.3`). Creates
      `shared-edge` (docker-resource-manager auto-creates it).
- [ ] **Verify `akadmin` login BEFORE any public exposure** — hit rick's
      Tailscale IP `:9000` directly. Do not proceed until this works.

## 5. Expose `auth.ktbcloud.com`
- [ ] **Merge PR #26** and redeploy the **`pangolin`** stack (Komodo). This
      attaches gerbil to `shared-edge` and activates the raw `authentik-router`.
- [ ] **DNS:** `auth.ktbcloud.com` → rick, **DNS-only (grey cloud)**. Not
      proxied — Pangolin/gerbil terminate TLS and issue the cert.
- [ ] Confirm the cert issues and the **OIDC discovery URL** loads publicly:
      `https://auth.ktbcloud.com/application/o/<app>/.well-known/openid-configuration`
      (or the base `https://auth.ktbcloud.com/` login).

> The `authentik-router` is **raw** — no badger/SSO middleware. If you ever see a
> redirect/login loop on `auth.ktbcloud.com`, something put SSO in front of
> Authentik; that must never happen (break-glass).

## 6. Validate blueprints against the running instance
The drafts in `files/blueprints/{pangolin-oidc,internal-forwardauth}.yaml` were
authored blind against **2026.5.3** — the `!Find`/`!KeyOf` tags, flow slugs
(`default-provider-authorization-implicit-consent`, …), scope mappings, and
signing key references are **guesses**.
- [ ] Apply/validate each blueprint against the live Authentik; fix in
      `files/blueprints/`.
- [ ] `internal-forwardauth`: `cookie_domain` = `ktbinternal.com`,
      `external_host` = `auth.ktbcloud.com` (already set).
- [ ] Mint the outpost token here → back-fill Infisical `/authentik-outpost`
      `AUTHENTIK_TOKEN` (step 2).

## 7. Pilot ONE native-OIDC app
- [ ] Wire **Forgejo or Immich** straight to Authentik (native OIDC, not through
      Pangolin). Validate the full login round-trip before touching Pangolin.

## 8. Pangolin → Authentik OIDC
- [ ] In Pangolin: **Server Admin → Identity Providers** → add Authentik as an
      external OIDC IdP.
- [ ] Copy Pangolin's generated **redirect URI** back into the Authentik provider
      (redirect mode: **Strict**).
- [ ] Flip **ONE** low-risk `*.ktbcloud.com` resource to SSO. **Plex = SSO OFF**
      (raw, app's own login).

## 9. Internal forward-auth plane
- [ ] Deploy **`authentik-outpost`** (`ghcr.io/goauthentik/proxy:2026.5.3`) on
      **littlebuddy** (Komodo).
- [ ] In `platform/edge/traefik/files/host.yml`: add the `authentik-forwardauth`
      forwardAuth middleware + the `/outpost.goauthentik.io/` router. Address =
      littlebuddy tailnet IP **`100.114.137.104:9000`**.
- [ ] Provider = **domain-level** proxy, cookie domain **`ktbinternal.com`**.
- [ ] Apply `mixins.proxyAddAuth(...)` to ONE no-OIDC internal service (e.g.
      sonarr) as the pilot.

## 10. Cut services over by tier
Native-OIDC first, forward-auth last.
- **native-OIDC:** openproject, immich, paperless, forgejo/gitea, komodo, frappe
- **forward-auth / raw:** the *arr stack, convertx, seerr, docuseal, infisical, twenty
- **raw (own login):** Plex
- **tailnet-only (no auth layer):** postgres, databasus, zerobyte, komodo-mcp

---

## Rollback notes
- Each step is reversible: pull the DNS record, revert the pangolin redeploy, or
  stop the `authentik` stack — nothing else depends on it until you cut a service
  over (step 8+).
- `authentik` runs **bundled** Postgres/Redis (NOT littlebuddy's shared-postgres)
  so the public IdP has no cross-Tailscale DB dependency. It needs its **own
  pg_dump/backup job** — not covered by databasus. (Debt, tracked separately.)

## References
- Compose install: https://docs.goauthentik.io/install-config/install/docker-compose/
- OAuth2 provider: https://docs.goauthentik.io/add-secure-apps/providers/oauth2
- Traefik forward-auth outpost: https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_traefik
- Pangolin OIDC IdP: https://docs.pangolin.net/manage/identity-providers/openid-connect
- Pangolin ↔ Authentik: https://integrations.goauthentik.io/networking/pangolin
