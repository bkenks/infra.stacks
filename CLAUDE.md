# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
Remember that a repo is a living project, changing daily. So, if something in this repository contradicts
an action, instruction, inquiries, etc. it is possible something has changed. In this scenario, just ask
about the contradiction.

## What this is

Self-hosted homelab monorepo. Each leaf directory under `src/` is a **stack** authored in
jsonnet, rendered to Docker Compose YAML in place on commit, and deployed by **Komodo**
across a fleet of Tailscale-connected hosts.

## The two rules that dominate everything

**An entrypoint names the files it writes.** It evaluates to an object whose top-level
fields are filenames without the extension, each value the document to put there, and every
file lands in the entrypoint's own directory: `{ compose: {...} }` renders `compose.yaml`,
and `{ compose: {...}, services: {...} }` renders both. One field or four, the shape is the
same. The entrypoint's own filename decides nothing — `# GENERATED from …` is what ties
output back to source. A field holding anything but an object is a hard error, which catches
the mistake this shape invites: returning a bare Compose document, whose top-level
`name:`/`networks:`/`volumes:` would otherwise be read as filenames. `*.libsonnet` is never
an entrypoint — it is only ever imported — and a dot-prefixed directory (`.old/`) is skipped
whole.

**Never edit a file whose first line is `# GENERATED from … — DO NOT EDIT.`** That header is
the ownership marker: the builder deletes every header-marked file the fresh build no longer
produces, which is what makes a rebuild total (a deleted stack or a renamed entrypoint leaves
nothing behind). A file without the header is hand-written; the build refuses to overwrite
one and never deletes it.

Generated output is committed, because Komodo clones this repo on the target host and
deploys out of `src/` directly.

## A stack is one hand-written file

| File | Hand-written? | Role |
|---|---|---|
| `stack.jsonnet` | yes | A `local refs = lib.Project {...}` — every name this stack owns — then `{ compose: <plain Compose> }`, one field per file it renders. |
| `compose.yaml` | no | The rendered manifest — what `docker compose` loads, and what Komodo watches and diffs. |
| `files/`, `templates/` | both | Bind-mounted config: nested `.jsonnet` entrypoints, their outputs, and hand-written assets (`files/entrypoint.sh`) side by side. |
| `README.md` | yes | Per-stack deploy notes. |

Under its `services:` field, `stack.jsonnet` is **plain Compose**. There is no `Service`
base and no `Stack` assembler — what you read is what gets rendered. The only things not
written literally are the names the manifest and the compose document have to agree on,
and those come out of the `refs` table above them.

Secrets arrive through the infisical-secrets Compose provider, which injects them straight
into the container's environment, so a manifest has no `${...}` left for compose to resolve
and a stack renders as one document. The single exception is
`src/platform/secrets-manager/infisical` — see **Secrets** below — which still splits
`compose` from `services` so an `env_file` can attach at the `include`, the one place a
`${VAR}` inside a manifest is interpolated from.

**Authoring guide with worked examples lives at `src/templates/stack/README.md`** — read it
before writing a new stack. `src/templates/stack/` is the canonical copy-me stack; it is a
real compiling stack, so a `devlib/` change that breaks it fails the build.

## Toolchain (mise)

`.config/mise/config.toml` pins the tools the build needs: `go-jsonnet` (the `jsonnet`
binary the builder shells out to), `uv` (the builder's runtime, which resolves its own
Python), `lefthook`, `yamllint` and `yq`. On a fresh clone run **`mise trust && mise
install`** — the trust is required per-machine before mise will act on a config, and
`install`'s postinstall hook runs `lefthook install` to wire up the git hooks.

## Render pipeline (exact commands)

`devlib/render.py` is the builder. It takes no arguments and always rebuilds everything:

```
mise run render     # or ./devlib/render.py directly
```

It (1) runs `jsonnet -J devlib` on every `.jsonnet` under `src/` and builds the whole output
set in memory, so a jsonnet failure aborts before anything on disk is touched, (2) refuses
to run if an output would land on a hand-written file, (3) deletes every header-marked file
the fresh set no longer contains, (4) writes each output beside its entrypoint.

An entrypoint must evaluate to a non-empty object of filename to document; each field is
manifested to YAML as `<field>.yaml` beside the entrypoint.

Normally you don't call it directly — **`.config/lefthook.yml` runs `mise run render` on
every pre-commit**. The builder prints every path it wrote or removed on **stdout** (the
summary goes to stderr), and lefthook pipes that list into `git add`, so a commit stages the
generated files and nothing else left unstaged on purpose. There is no glob and no
incremental mode: a rebuild is total, so a deleted stack, a renamed entrypoint, and a
`registry.libsonnet` edit reaching every stack are all handled by the same single job.

## The jsonnet library (`devlib/`, reached via the `-J devlib` jpath)

A stack imports exactly one file — `local lib = import 'lib.libsonnet';` — from any depth
under `src/`.

- **`lib.libsonnet`** — the single entrypoint. Re-exports everything in `collections`
  (`lib.role`, `lib.domain`, `lib.dirs`, `lib.ip`, `lib.mounts`, `lib.labels`,
  `lib.condition`, `lib.restart`) and adds `lib.registry`, `lib.templates`,
  `lib.collections`, `lib.Project`, `lib.SecretsProvider(key)`, `lib.secretsReady`, and —
  for the Infisical stack alone — `lib.Secret(key)` and `lib.SecretOrBootstrap(key)`.
- **`collections.libsonnet`** — raw constants: values that depend on nothing, only a
  spelling or a default. Nothing here refers to anything else.
- **`templates.libsonnet`** — the shapes a name can have, holding no values:
  `Endpoint.HostGroup` (`Host`), `Endpoint.ServiceGroup.Service` (`Container` / `Host` /
  `Proxy`), `SharedNetwork`, and `Project` (`Service`, `Volume`, and the `compose`
  document).
- **`registry.libsonnet`** — the global version of a stack's `refs` table: a value
  lands here the moment a *second* stack needs it. That is the line against
  `collections` — constants that depend on nothing stay there and are never repeated here.
  **Reference by KEY, never by string literal**:
  `reg.endpoint.serviceGroup.postgres.host.addr` fails at compile time on a typo;
  `'littlebuddy.internal:6109'` fails silently at runtime. Holds `network.shared`,
  `endpoint.hostGroup` (the inventory — `ref` is the host's `.internal` name),
  `endpoint.serviceGroup`, `dir` (only paths a *second* stack reads), and `infisical`
  (the server's `address` plus every project's secret bundles, flattened into
  `infisical.catalog` for `lib.SecretsProvider`).

## Network model (non-obvious)

This is a multi-node fleet, so the two directions are different mechanisms and the registry
names both.

Each stack gets a private `default` bridge named after the project, written literally:
`networks: { default: { name: refs.name } }`.

**Container to container, on one host** — a shared Docker network out of
`reg.network.shared`. The split is ownership: the owning stack declares it plain, every
other stack declares it `external: true`, and each participating service lists it by
`<net>.name`. Compose creates an `external` network for nobody, so a stack that attaches to
one that does not exist yet fails to come up instead of quietly building its own empty copy.

**Host to host** — the `.internal` zone, resolved by the CoreDNS every host runs. Publish
the port and dial `reg.endpoint.serviceGroup.<x>.host.addr`, which pairs the service's port
with its host's `ref`. Which host runs a service is a fact of that stack, so it lives on
the registry entry (`host:: service.Host { on:: host.littlebuddy, port:: '6109' }`) and no
consumer retypes it. The shared Postgres cluster (`databases/postgres`) is single-sourced
both ways: `.container.addr` on littlebuddy, `.host.addr` from anywhere else.

## Secrets (Infisical)

Self-hosted Infisical is the store, read through the **infisical-secrets** Compose provider
(`bkenks/collection_compose-extensions`). Compose runs the provider as a subprocess at `up`
and injects every secret in the bundle as a plain environment variable — under its own
Infisical name — into each service that declares `depends_on` on the provider service. The
binary has to be on the `PATH` of whatever runs `docker compose` on the host; each host's
machine identity lives in the dotenv file at `registry.path.file.infisical_creds`.

In a stack: register the bundle in the right Infisical project's `secretsMap` in
`registry.libsonnet` (they flatten into `infisical.catalog`), add
`[lib.collections.role.SECRETS]: lib.SecretsProvider('<key>')` to `services:`, and add
`lib.secretsReady` to the `depends_on` of every service that reads one. Nothing is injected
into a service that does not depend on the provider.

**Store each secret under exactly the name the container reads.** There is no compose-level
interpolation left, so nothing can rename a value or assemble one: a password two services
read under two names is stored twice, and a connection string is stored whole rather than
built from a user and a password. A literal written in `environment:` that the bundle also
carries is overwritten by the bundle's, which is how a default stays overridable per host.
A secret that must land as a *file* needs a `pre_start` hook — see
`platform/backup-manager/databasus`.

`lib.Secret(key)` / `lib.SecretOrBootstrap(key)` survive for exactly one stack: the Infisical
server's own, which cannot ask itself for its secrets before it is up. It keeps the two-
document shape and an `env_file` the control plane writes. Do not use them anywhere else.

## Deployment (Komodo)

All Komodo resources — stacks, servers, variables, procedures — are declared in one
authoritative resource-sync file, `files/komodo_config/sync.toml` (`managed = true`). It
lives outside `src/` because Komodo commits back to it, and generated output must never be a
write target. Each stack sets `linked_repo = "infra.stacks"` + `run_directory` + `server`;
Komodo clones the repo on the target host and runs `docker compose` there. **`run_directory`
is the stack's own source directory** — `./src/platform/edge/cloudflared` — and every entry
carries `file_paths = ["compose.yaml"]`.

**"[Komodo] Commit Sync" commits are Komodo writing UI-side changes back into that TOML** —
the sync is bidirectional, so the TOML stays canonical. The TOML is currently not synced on
a schedule so there may be drift between what exists in the TOML vs. what is actually in Komodo.
So, if something doesn't exist in the TOML, either don't worry about it if it's not critical, or
if some other action depends on it, refer to Komodo directly via MCP to check state and resources.

[Aug 26, 2026] NOTE: We are in a trial phase of testing out Dockhand as a possible replacement
for Komodo. Currently Dockhand is only used for stacks under the KTB Software business and it's
config is in another repo, deployed to a host not connected to this infra.

## Top-level org

- `src/` — every stack. `apps/` (user-facing: `business/`, `media/`, `personal/`,
  `storage/`), `platform/` (infra: `edge/`, `container-manager/`, `secrets-manager/`,
  `backup-manager/`, `dashboard/`, `identity/`), `databases/` (`postgres/`), `tools/`
  (`devops/`, `komodo-mcp/`), and `templates/stack/` — the canonical stack template +
  authoring guide.
- `devlib/` — the jsonnet library and `render.py`, the builder.
- `.config/` — `mise/config.toml` (toolchain + tasks), `lefthook.yml` (the pre-commit hook),
  `yamllint.yml`.
- `files/komodo_config/sync.toml` — the Komodo resource-sync file.
