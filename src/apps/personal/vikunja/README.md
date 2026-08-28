# vikunja

[Vikunja](https://vikunja.io/) — self-hosted task manager with List, Kanban, Gantt and Table
views over the same project. Reached at `vikunja.ktbinternal.com` via Traefik → port 3456.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

**Deploying it: [DEPLOY.md](./DEPLOY.md).** This file is what the stack is and why it is shaped
the way it is.

## Shape

App plus its own dedicated Postgres, deployed via Komodo on `littlebuddy`, published on
`127.0.0.1:18026`.

`db` is this stack's own Postgres, not the shared cluster. Vikunja reads discrete
`VIKUNJA_DATABASE_*` values rather than one connection URL, so the shared cluster's usual
payoff — storing `DATABASE_URL` whole in the bundle — buys nothing here, and a dedicated
instance keeps the whole trial to one stack that deletes cleanly.

Secrets come from Infisical `/vikunja` through the infisical-secrets provider:
`VIKUNJA_SERVICE_SECRET` and `VIKUNJA_DATABASE_PASSWORD` (app), `POSTGRES_PASSWORD` (db). The
last two hold the same password, so the bundle carries it under both names.

## Two things the upstream image forces

Both follow from Vikunja shipping `FROM scratch` with `USER 1000`:

- **Attachments are a host bind mount**, `/srv/docker/bind-mounts/apps/vikunja/files`, not a
  named volume. The image never creates that directory, so an empty named volume has nothing
  to copy ownership from and lands root-owned — uploads then fail while the app otherwise
  looks fine. The stack's `pre_deploy` in `files/komodo_config/sync.toml` does the `mkdir -p`
  and `chown 1000`.
- **The app service has no healthcheck.** No shell, no curl, no wget, and the `vikunja` binary
  has no health subcommand to exec instead. `db` is healthchecked normally and the app waits
  on it.

## Not wired up yet

The DB port is not published, so `databasus` on `rick` cannot back this up — publish it on
loopback and add a registry endpoint if the trial sticks.
