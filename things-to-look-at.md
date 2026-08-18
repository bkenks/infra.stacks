# From Claude — devlib migration

Every stack under `src/` now compiles against the rewritten `devlib/`. `./devlib/render.py`
renders 52 entrypoints clean and is idempotent. Things worth your eyes:

## devlib changes I made (all four were approved, plus two you should confirm)

Approved bug fixes:

1. `templates.Project.Service.ext` was `project.name + '_' + self.compose` — `compose` is a
   field of `Project`, not `Service`, so any use errored. Now `self.role`.
2. `templates.Endpoint.HostGroup.Host.ref` read `hostGroup.internal`; the field is `zone`.
   `zone` is now `'internal'` (no leading dot) and `ref` is `alias + '.' + zone`.
3. `templates...Proxy` required `subdomain` while the registry passed `sub`, and `fqdn` was
   `'%s.$s'` — a literal `$s`. Both fixed; registry entries now pass `subdomain`.
4. `lib.Secret` referenced `self.registry.secretPath` / `registry.infisical.catalog`, none of
   which existed. Added `infisical.catalog` — a flat merge of every project's `secretsMap` —
   and `lib.Secret(key)` returns `catalog[key].outFilePath` behind an assert.

Two more I did without asking, because they follow from your own rule (a value another stack
needs lives in the registry) — say the word and I'll back either out:

5. **`Endpoint...Host` gained `on::`, `addr` and `url`.** Which host runs Postgres is a fact
   of the postgres stack, so `postgres.host` is now
   `service.Host { on:: host.littlebuddy, port:: '6109' }` and `.addr` is
   `littlebuddy.internal:6109`. Without it every cross-host consumer retypes the hostname.
   Assignments came from `sync.toml`: postgres -> littlebuddy, infisical -> rick.
6. **`Endpoint...Container` gained `addr`** (`postgres-db:5432`), the same-host counterpart.
   `url()` stays a function; it is called as `.url()` at the one call site (infisical).
   Also **`registry.dir.fileBrowser`** is back — terraria mounts a world under the tree
   file-browser-quantum serves, so it is a genuine cross-stack path.

Per your "collections owns constants, registry owns cross-stack values": registry's `path`,
`ip` and `domain` blocks are gone, and it imports `collections` for those. `homektb`,
`stackform` and `couchpotatoes` were only in the registry copy and no stack referenced any
of them, so they are dropped rather than merged into `collections`.

Also fixed in registry: `t_Secrets.projectId` read `project.id` off the un-parameterised
`t_InfisProject`, so it errored for every bundle. Each project group now extends
`t_InfisProject` directly, so its own `id` resolves.

## Live behaviour changes on the next deploy

1. **`extra_hosts: host.docker.internal:host-gateway` is gone from all 9 services** that had
   it (komodo, komodo-mcp, newt, databasus, docuseal, openproject x4). Anything that was
   actually dialling `host.docker.internal` at runtime — configured in a UI rather than in
   these files — will stop resolving. **databasus is the one to check**: its backup targets
   are configured inside the app, and they need to become `littlebuddy.internal:6109`.
2. **zerobyte `BASE_URL`** is now `http://littlebuddy.internal:4096`, was `http://10.100.0.21:4096`.
   Depends on CoreDNS resolving `littlebuddy.internal` from that container.
3. **openproject `cron` and `seeder` now join `shared__postgres_db`.** They were carrying
   `DATABASE_URL: postgres-db:5432` with no route to that name — only `web`, `worker` and
   `hocuspocus` were on the shared network. The seeder runs the migrations, so this was a
   real break; the shared-network membership moved into the `railsApp` local that all four
   share.

## Other notes

- `files/komodo_config/sync.toml`: homarr's `run_directory` now points at
  `./src/platform/dashboard/homarr` (you moved the stack); fbq's `ignore_services = ["init"]`
  is dropped since you removed the init service. `pangolin-client` still names
  `./src/platform/edge/pangolin-client`, which does not exist — pre-existing, untouched.
- Nothing creates `shared__postgres_db`, `shared__paperless_db`, `shared__forgejo_db` or
  `shared__infisical_db`: every stack declares them `external: true`, so they are made out
  of band. Only `shared__ts-gateway` has an owner (tailscale). Same as before this change.
- `.old/` stacks still import the removed `lib.Service` / `lib.Stack` API. Render skips
  dot-dirs so they don't break the build, but they are dead code.
- `CLAUDE.md` and `src/templates/stack/README.md` are rewritten for the new model — the
  network section in both now describes shared networks (same host) and the `.internal`
  zone (host to host) as the two separate mechanisms they are.
