# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Self-hosted homelab monorepo. Each leaf directory under `src/` is a **stack** authored in
jsonnet, rendered to Docker Compose YAML in place on commit, and deployed by **Komodo**
across a fleet of Tailscale-connected hosts.

## The two rules that dominate everything

**One entrypoint, one output.** `services.jsonnet` renders to `services.yaml` beside it;
`compose.jsonnet` renders to `compose.yaml`. Same directory, same name, `.jsonnet` ->
`.yaml`. There is no name-mangling and no multi-file entrypoint: a jsonnet file that needs
to produce two files is two jsonnet files. `*.libsonnet` is never an entrypoint — it is
only ever imported — and a dot-prefixed directory (`.old/`) is skipped whole.

**Never edit a file whose first line is `# GENERATED from … — DO NOT EDIT.`** That header is
the ownership marker: the builder deletes every header-marked file the fresh build no longer
produces, which is what makes a rebuild total (a deleted stack or a renamed entrypoint leaves
nothing behind). A file without the header is hand-written; the build refuses to overwrite
one and never deletes it.

Generated output is committed, because Komodo clones this repo on the target host and
deploys out of `src/` directly.

## A stack is three hand-written files

| File | Hand-written? | Role |
|---|---|---|
| `refs.libsonnet` | yes | Every name this stack owns — project name, service keys, container names, volume names, env files. Imported by the other two. |
| `services.jsonnet` | yes | The manifest: plain Compose. **This is what Komodo watches and diffs.** |
| `compose.jsonnet` | yes | One line: `(import 'refs.libsonnet').compose`. |
| `services.yaml` | no | Rendered manifest. |
| `compose.yaml` | no | What `docker compose` loads: project name + `include:` (+ `env_file:`). |
| `files/`, `templates/` | both | Bind-mounted config: nested `.jsonnet` entrypoints, their outputs, and hand-written assets (`files/entrypoint.sh`) side by side. |
| `README.md` | yes | Per-stack deploy notes. |

`services.jsonnet` is **plain Compose**. There is no `Service` base and no `Stack`
assembler — what you read is what gets rendered. The only things not written literally are
the names two files have to agree on, and those come out of `refs.libsonnet`.

`compose.jsonnet` exists as its own file because `env_file` has to attach at the `include`,
not at the service: `${VAR:?err}` inside `services.yaml` is interpolated from the include's
env file, whereas a service-level `env_file:` only reaches the container's environment and
would leave every `${...}` in the manifest unresolved.

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

An entrypoint must evaluate to a non-empty object, which is manifested to YAML.

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
  `lib.collections`, `lib.Project`, `lib.Secret(key)` and `lib.SecretOrBootstrap(key)`.
- **`collections.libsonnet`** — raw constants: values that depend on nothing, only a
  spelling or a default. Nothing here refers to anything else.
- **`templates.libsonnet`** — the shapes a name can have, holding no values:
  `Endpoint.HostGroup` (`Host`), `Endpoint.ServiceGroup.Service` (`Container` / `Host` /
  `Proxy`), `SharedNetwork`, and `Project` (`Service`, `Volume`, and the `compose`
  document).
- **`registry.libsonnet`** — the global version of a stack's `refs.libsonnet`: a value
  lands here the moment a *second* stack needs it. That is the line against
  `collections` — constants that depend on nothing stay there and are never repeated here.
  **Reference by KEY, never by string literal**:
  `reg.endpoint.serviceGroup.postgres.host.addr` fails at compile time on a typo;
  `'littlebuddy.internal:6109'` fails silently at runtime. Holds `network.shared`,
  `endpoint.hostGroup` (the inventory — `ref` is the host's `.internal` name),
  `endpoint.serviceGroup`, `dir` (only paths a *second* stack reads), and `infisical`
  (every project's secret bundles, flattened into `infisical.catalog` for `lib.Secret`).

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

Self-hosted Infisical is the store; the **infisical-agent** runs on every host and renders
that host's secrets to `/dev/shm/<stack>.env` (RAM, never disk). The agent's per-service
config fragments live in `src/platform/secrets-manager/infisical/templates/` and are
**hand-written**; a host opts in via its `AGENT_SERVICES` list.

In a stack, register the bundle in the right Infisical project's `secretsMap` in
`registry.libsonnet` (they flatten into `infisical.catalog`), put
`lib.Secret('<key>')` in `refs.libsonnet`'s `envFiles`, and reference vars as `${VAR:?err}`
so a missing secret aborts the deploy. Consumer and agent derive the path from the same
entry, so they cannot disagree; `lib.SecretOrBootstrap(key)` is the same path wrapped in
`${ANSIBLE_SECRETS_FILE:-…}` for stacks the control plane brings up before the agent exists.

## Deployment (Komodo)

All Komodo resources — stacks, servers, variables, procedures — are declared in one
authoritative resource-sync file, `files/komodo_config/sync.toml` (`managed = true`). It
lives outside `src/` because Komodo commits back to it, and generated output must never be a
write target. Each stack sets `linked_repo = "infra.stacks"` + `run_directory` + `server`;
Komodo clones the repo on the target host and runs `docker compose` there. **`run_directory`
is the stack's own source directory** — `./src/platform/edge/cloudflared` — and every entry
carries `file_paths = ["compose.yaml"]`.

**"[Komodo] Commit Sync" commits are Komodo writing UI-side changes back into that TOML** —
the sync is bidirectional, so the TOML stays canonical.

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
