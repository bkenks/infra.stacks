# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Self-hosted homelab monorepo. Each leaf directory is a **stack** authored in jsonnet, rendered to Docker Compose YAML on commit, and deployed by **Komodo** across a fleet of Tailscale-connected hosts.

## The one rule that dominates everything

**`src/` holds every stack and nothing else. `.deploy/` holds nothing but build output.**

You edit stacks in `src/`. `.deploy/` is a build artifact — it mirrors the *contents* of `src/`, so `src/apps/business/n8n` builds to `.deploy/apps/business/n8n` — and is wiped and rebuilt from scratch on every commit. **Never edit anything under `.deploy/`; it will not survive the next commit.** It is committed to git because Komodo clones this repo on the target host and deploys out of it.

Everything that is not a stack stays out of `src/`: `.mise/` (the builder), `lib/` (the jsonnet library), `komodo-config-sync.toml`, `lefthook.yml`, `mise.toml`, docs. That is what lets the builder have no ignore list — anything in `src/` is either a jsonnet entrypoint or an asset to copy.

## Toolchain (mise)

`mise.toml` pins the three tools the build needs: `go-jsonnet` (the `jsonnet` binary the builder shells out to), `uv` (the builder's runtime, which resolves its own Python), and `lefthook`. On a fresh clone run **`./bootstrap.sh`** — it trusts `mise.toml` (mise requires this per-machine before it will act on a config) and runs `mise install`, whose postinstall hook runs `lefthook install` to wire up the git hooks. `mise run render` is the render task lefthook itself invokes; it is **not declared in `mise.toml`** — mise discovers executables under `.mise/tasks/` by filename (extension stripped), so the file `.mise/tasks/render.py` *is* the `render` task.

## Render pipeline (exact commands)

`.mise/tasks/render.py` is the builder (a `uv run` self-contained script; the `jsonnet` binary comes from mise). It takes **no arguments** and always rebuilds everything — ~0.5s for all 39 entrypoints:

```
mise run render     # or ./.mise/tasks/render.py directly
```

It (1) removes `.deploy/`, (2) copies every non-jsonnet file in `src/` to its mirrored path, (3) runs `jsonnet -J <repo root>` on each `.jsonnet` and writes its outputs into that entrypoint's own mirrored directory. So `src/platform/edge/dnsmasq/files/hosts.jsonnet` → `.deploy/platform/edge/dnsmasq/files/hosts`, and every `./files/…` bind mount in the generated compose keeps working unchanged. An entrypoint must evaluate to `{'<bare-filename>': content, …}`; dict content renders to YAML, string content is written verbatim (Infisical fragments carry Go-template bytes that must not be reparsed).

Normally you don't call it directly — **`lefthook.yml` runs `mise run render` on every pre-commit** and `git add -A -- .deploy`. There is no glob and no incremental mode: a rebuild is total, so a deleted stack, a renamed output, a `registry.libsonnet` edit reaching every stack, and a plain asset edit are all handled by the same single job.

Only `*.libsonnet` (imported, never copied) and `.DS_Store` are skipped. Everything else in `src/` — including per-stack `README.md` and `tests/` — is copied verbatim, so a stack's `tests/render_compose.sh` runs unchanged from its `.deploy/` counterpart.

## The jsonnet library (`lib/`, reached via the repo-root `-J` jpath)

A stack imports exactly one file — `local lib = import 'lib/lib.libsonnet';` — from any depth under `src/`.

- **`lib.libsonnet`** — the single entrypoint. Re-exports `Service`/`Stack`, and adds `render(projectName, stack, envFiles=[])` (the contract every `compose.jsonnet` ends with — emits `compose.yaml` with the project name + `include:`, `env_file:` only when secrets exist, and `compose.stack.yaml` with the real manifest), `Secret(key)` / `SecretOrBootstrap(key)`, `komodoSkip`, `toEnv(obj)`, and `registry`.
- **`compose.libsonnet`** — `Service` and `Stack`. `Service` derives `container_name` (`<stack>_<role>`), `restart`, the network alias, and volume mounts from late-bound `self.stack`/`self.role`; `Stack(name, services, networks=null)` binds those in, keys services by bare role, and registers top-level volumes from what mounts them. Every derived field is a plain field, so a stack overrides one by writing it again — that is how `postgres-db`, komodo's `komodo_core` alias, and pangolin's unprefixed `gerbil`/`traefik` survive.
- **`registry.libsonnet`** — source of truth for anything crossing stack boundaries. **Reference by KEY, never by string literal**: `reg.endpoint.postgres.host` fails at compile time on a typo; `'host.docker.internal:6109'` fails silently at runtime. Holds: `hosts` (the host inventory, keyed by short name, `ip` = Tailscale addr — feeds dnsmasq and the Komodo server list), `role` (the service-key vocabulary), `domains`, `endpoint`, `dirs`, `ips`, `networks`, and `infisical.catalog` (every renderable secret bundle).

`Stack` takes the services as `function(ref) {...}`, called twice: once for its keys, once with `ref` — a table mapping each declared role to the name it will actually carry. Cross-service references go through `ref[role.DB]`, so naming a role the stack does not declare fails at evaluation rather than in a container that never starts.

**Authoring guide with worked examples lives at `src/.template/README.md`** — read it before writing a new stack. `src/.template/` is the canonical copy-me stack; it is a real compiling stack, so a lib change that breaks it fails the build.

## Stack directory convention

A stack dir in the **source tree** holds only hand-edited files:

| File | Role |
|---|---|
| `compose.jsonnet` | Source of truth — ends in `lib.render(...)`. |
| `files/` | Bind-mounted config; may hold its own nested `.jsonnet` entrypoint (e.g. `files/hosts.jsonnet`) and hand-written assets (e.g. `files/entrypoint.sh`). |
| `README.md` | Per-stack deploy notes. Not copied to `.deploy/`. |

Its counterpart at `.deploy/<same path>` is what actually deploys:

| File | Role |
|---|---|
| `compose.yaml` | What `docker compose` loads: project name + `include:` (+ `env_file:`). |
| `compose.stack.yaml` | The real manifest; **this is the file Komodo watches/diffs**. |
| `files/`, `templates/` | Rendered outputs alongside copied assets, at the same relative paths the compose refers to. |

## Network model (non-obvious)

There are **no shared Docker networks**. Each stack gets only a private `default` bridge. Cross-stack traffic goes over published host ports dialed as `host.docker.internal:<port>` with `extra_hosts: ['host.docker.internal:host-gateway']` on the consumer. The shared Postgres cluster (`databases/postgres`) is single-sourced this way via `reg.endpoint.postgres.host`.

## Secrets (Infisical)

Self-hosted Infisical is the store; the **infisical-agent** runs on every host and renders that host's secrets to `/dev/shm/<stack>.env` (RAM, never disk). To add a secret bundle: register it in `registry.libsonnet` `infisical.catalog`, which `templates/services.jsonnet` bakes into a per-service agent fragment; a host opts in via its `AGENT_SERVICES` list. In a stack, pass `lib.Secret('<catalogue-key>')` to `lib.render` and reference vars as `${VAR:?err}` so a missing secret aborts the deploy. Producer and consumer derive the path from the same catalogue entry, so they cannot disagree; `lib.SecretOrBootstrap(key)` is the same path wrapped in `${ANSIBLE_SECRETS_FILE:-…}` for stacks the control plane brings up before the agent exists.

## Deployment (Komodo)

All Komodo resources — stacks, servers, variables, procedures — are declared in one authoritative resource-sync file: `komodo-config-sync.toml` at the repo root (`managed = true`). It lives outside `src/` because Komodo commits back to it, and a build artifact must never be a write target. Each stack sets `linked_repo = "infra.stacks"` + `run_directory` + `server`; Komodo clones the repo on the target host and runs `docker compose` there. **`run_directory` points into the build tree** — `./.deploy/platform/edge/dnsmasq`, not `./platform/edge/dnsmasq`. The same stack dir is deployed to many hosts as separate entries.

**"[Komodo] Commit Sync" commits are Komodo writing UI-side changes back into that TOML** — the sync is bidirectional, so the TOML stays canonical.

## Top-level org

- `src/` — every stack. `apps/` (user-facing: `business/`, `media/`, `personal/`), `platform/` (infra: `edge/`, `container-manager/`, `secrets-manager/`, `backup-manager/`, `grist/`), `databases/` (`postgres/`), `tools/` (`devops/`, `komodo-mcp/`, `termix/`), and `.template/` — the canonical stack template + authoring guide. (`src/template/` and `src/apps/business/templates/` are separate scaffolding/reference stacks.)
- `.mise/tasks/render.py` — the builder, auto-discovered by mise as the `render` task.
- `lib/` — `lib.libsonnet` (the one import), `compose.libsonnet`, `registry.libsonnet`.
- `komodo-config-sync.toml` — the Komodo resource-sync file.
- `.deploy/` — build output. Generated; never edit.
