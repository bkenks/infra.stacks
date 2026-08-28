# vikunja

[Vikunja](https://vikunja.io/) — self-hosted task manager with List, Kanban, Gantt and Table
views over the same project. Reached at `vikunja.ktbinternal.com` via Traefik → port 3456.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Deploy

Deployed via Komodo. Secrets come from Infisical `/vikunja` through the infisical-secrets
provider: `VIKUNJA_SERVICE_SECRET` and `VIKUNJA_DATABASE_PASSWORD` (app), `POSTGRES_PASSWORD`
(db). The last two hold the same password, so the bundle carries it under both names. **Store
all three before the first `up`.** `db` is this stack's own dedicated Postgres, not the shared
instance — Vikunja reads discrete `VIKUNJA_DATABASE_*` values rather than one connection URL,
so the shared cluster buys nothing here.

`VIKUNJA_SERVICE_SECRET` signs JWTs. Left unset, Vikunja generates a new one on every start
and every session is invalidated on restart, so it is a real secret, not a nicety.

## Two things the upstream image forces

Both are consequences of Vikunja shipping `FROM scratch` with `USER 1000`:

- **Attachments are a host bind mount**, `/srv/docker/bind-mounts/apps/vikunja/files`, not a
  named volume. The image never creates that directory, so an empty named volume has nothing
  to copy ownership from and lands root-owned, and uploads fail. The stack's `pre_deploy` in
  `files/komodo_config/sync.toml` does the `mkdir -p` + `chown 1000`.
- **The app service has no healthcheck.** No shell, no curl, no wget, and the `vikunja` binary
  has no health subcommand. `db` is healthchecked normally and the app waits on it.

## First run

Registration is on (`VIKUNJA_SERVICE_ENABLEREGISTRATION: 'true'`) so the first account can be
made through the UI. Flip it to `'false'` and redeploy once it exists — Vikunja has no invite
flow, so anything else leaves the instance self-serve.

## iOS

The official Vikunja iOS app has no Kanban view yet. [mDone](https://apps.apple.com/us/app/mdone/id6760613430)
(free, iPhone/iPad/Mac) does, and talks only to this server.

## Not wired up yet

The DB port is not published, so `databasus` on `rick` cannot back this up — publish it on
loopback and add a registry endpoint if the trial sticks.
