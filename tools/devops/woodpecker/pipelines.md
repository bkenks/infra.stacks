# Woodpecker CI — Setup & Adding a Pipeline

> 📚 System architecture and the *why* live in Notion → **Architecture — How It All
> Connects**. This doc covers how Woodpecker is wired and how to add a CI pipeline to a
> repo. The stack's own deploy/secrets detail is in [`setup.md`](./setup.md).

## What it is

Woodpecker CI is a lightweight, Forgejo-integrated CI/CD engine — a **server**
(UI/API + gRPC) plus an **agent** that runs pipeline steps as containers via the host
Docker socket.

- **URL:** https://peck.homektb.com (Forgejo OAuth login)
- **Host:** littlebuddy (control plane). Deployed via Komodo as the `woodpecker-prod` stack.
- **Stack source:** `stack.infra/woodpecker` (server + agent, SQLite state, Traefik at
  `peck.homektb.com`).
- **Forge:** self-hosted Forgejo at `https://fj.homektb.com`.

## How the stack is wired (one-time, already done)

- **Forgejo OAuth2 app** — lets Woodpecker log users in and read their repos. Redirect URI
  `https://peck.homektb.com/authorize`. Its client ID/secret and the server↔agent
  gRPC `WOODPECKER_AGENT_SECRET` live in Infisical under `/woodpecker`, rendered to
  `/dev/shm/woodpecker.env` on littlebuddy by the infisical-agent (template
  `woodpecker.tpl` in `stack.node/infisical-agent`).
- **Privileged buildx plugin** — `WOODPECKER_PLUGINS_PRIVILEGED` in
  [`container-envs/server.env`](./container-envs/server.env) lets the docker-buildx plugin
  run privileged (it builds images via Docker-in-Docker). See the gotcha below.

## Two separate secret systems — don't confuse them

1. **Stack secrets** (the Woodpecker *server's* own OAuth + agent secret) → Infisical
   `/woodpecker` → `/dev/shm/woodpecker.env` → compose `env_file`. Same model as every
   other stack.
2. **Pipeline secrets** (e.g. a registry token a pipeline needs) → **Woodpecker-native
   secrets**, stored in Woodpecker's own database (the `woodpecker-server-data` volume),
   added in the Woodpecker UI, referenced in `.woodpecker.yml` via `from_secret:`. **These
   never touch Infisical.**

## Adding a CI pipeline to a repo

1. **The repo must be a first-class Forgejo repo** — not a Forgejo *pull-mirror*.
   Pull-mirrors are read-only and don't fire the push/tag/release webhooks Woodpecker
   needs. (If it's a pull-mirror: Forgejo repo → Settings → Danger Zone → *Convert to
   Regular Repository*, then keep only the push-mirror out to GitHub.)
2. **Activate the repo in Woodpecker** — log into https://peck.homektb.com, find the
   repo, enable it. This auto-installs the webhook into the Forgejo repo.
3. **Add any pipeline secrets** the `.woodpecker.yml` references — Woodpecker UI → repo (or
   org) → Settings → Secrets. Mind each secret's **event filter** (a secret not allowed on
   the triggering event arrives empty).
4. **Add `.woodpecker.yml`** at the repo root (or a `.woodpecker/` dir for multiple
   workflows) and commit it to the branch/tag that will trigger. Woodpecker reads the
   config from whatever ref fired the event.
5. **Trigger** per the pipeline's `when:` filter (push / tag / release / manual).

### Gotchas

- **Privileged plugin tag must match exactly.** `WOODPECKER_PLUGINS_PRIVILEGED` matches the
  image *including the tag* — a tag-less entry only matches `:latest`. So the tag there must
  equal the plugin tag pinned in `.woodpecker.yml`, and the two move together on every
  version bump.
- **Secret event filter** — if a build can't authenticate, check the secret is allowed on
  the event (e.g. `release`).
- **`CI_COMMIT_TAG` is built-in**, not user-set — Woodpecker populates it from the git tag
  on tag/release events. You only choose the tag name when cutting the release.

---

## Worked example — `stackform_website` (release → build → push)

**Goal:** when a release is published in Forgejo, build the Next.js production image and
push it to Forgejo's container registry (packages).

**Flow:** publish a Forgejo release with a bare-semver tag (e.g. `1.0.9`) → Forgejo fires
the `release` webhook → Woodpecker runs the buildx plugin → image pushed to
`fj.homektb.com/stackform-hq/stackform_website:1.0.9` (+ `latest`) → visible under
the org's **Packages** tab.

**Pipeline** (`stackform_website/.woodpecker.yml`):

```yaml
when:
  - event: release

steps:
  - name: build-and-push
    image: woodpeckerci/plugin-docker-buildx:6.1.0
    settings:
      registry: fj.homektb.com
      repo: fj.homektb.com/stackform-hq/stackform_website
      dockerfile: Dockerfile
      platforms: linux/amd64
      tags:
        - ${CI_COMMIT_TAG}   # the release tag, e.g. 1.0.9
        - latest
      build_args:
        - NEXT_PUBLIC_SERVER_URL=https://stackform.app
      username:
        from_secret: forgejo_registry_user
      password:
        from_secret: forgejo_registry_token
```

**Notes on each piece:**

- `when: event: release` — only runs on a published release.
- `${CI_COMMIT_TAG}` → the image tag (bare semver to match the repo's `SITE__VERS_TAG`
  convention). Also tags `latest`.
- `build_args` bakes `NEXT_PUBLIC_SERVER_URL` in at build time (Next.js inlines
  `NEXT_PUBLIC_*` into the client bundle).
- `username`/`password` come from **Woodpecker secrets** `forgejo_registry_user` /
  `forgejo_registry_token` (below).

**Pipeline secrets to add in Woodpecker** (repo → Settings → Secrets, allowed on the
`release` event):

- `forgejo_registry_user` — a Forgejo username.
- `forgejo_registry_token` — a Forgejo token (user's Settings → Applications → Generate
  Token) scoped **`read:package` + `write:package`**.

**Server config this example depends on:**
`WOODPECKER_PLUGINS_PRIVILEGED=woodpeckerci/plugin-docker-buildx:6.1.0` in
[`container-envs/server.env`](./container-envs/server.env) — the tag matches the plugin tag
in the pipeline.

**Open follow-up:** the deploy compose (`stackform_website/compose/yamls/service.yaml`)
still pulls `ghcr.io/stackform-hq/stackform_website`. To consume the CI-built image,
repoint `image:` to the Forgejo registry path and bump `SITE__VERS_TAG`.
