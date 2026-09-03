# How infra.stacks works

Every directory under `src/<area>/<app>/` holding a `stack.pkl` is one Docker Compose
stack. Pkl renders it to the `compose.yaml` beside it (plus `bootstrap.yaml`,
`services.yaml`, or config files where a stack declares them); the rendered YAML is
committed, and Komodo or Ansible deploys it from that directory. The deploy pipeline never
runs Pkl.

## Layers

| Layer | Where | What |
| --- | --- | --- |
| pkl-compose | `.vendir/pkl-compose/` (vendored from `bkenks/pkl-compose` at a git tag) | Typed compose schema, role-keyed services, derived container/volume/network names. |
| infra | `src/lib/` (local Pkl package `@infra`) | `Stack.pkl` (header + `output.files`), `registry.pkl` (every value that crosses a stack boundary), `collections.pkl` (constants), `secrets.pkl` (the infisical-secrets provider). |
| stacks | `src/**/stack.pkl` | One module per stack; amends `@infra/Stack.pkl`. |

`src/templates/stack/` is the reference stack and the authoring guide (`README.md` there).

## Naming

Derived by pkl-compose from the project `name` and each service's role:

| Resource | Name |
| --- | --- |
| container | `<name>-<role>` |
| hostname | `<role>` |
| data volume | `<name>-<role>_<purpose>` (compose key `<role>_<purpose>`) |
| network | `<name>_<purpose>`, or the shared network's own name when `external` |

A stack that must keep a name other systems dial writes `container_name` explicitly
(`databases/postgres`, `platform/edge/pangolin`).

## Commands

| Task | Does |
| --- | --- |
| `mise run render` | `scripts/render.sh`: evaluates every `src/**/stack.pkl` with `pkl eval -m`, refuses to overwrite hand-written YAML, removes stale generated files, prints the owned paths. Lefthook runs it on every commit. |
| `mise run check` | `docker compose config --quiet` over every `compose.yaml` and `bootstrap.yaml`. |
| `mise run test` | `pkl test`: facts on the registry and snapshots of representative stacks under `tests/`. |
| `mise run deps:sync` | `vendir sync` + `pkl project resolve` after bumping `vendir.yml`. |

## Cross-stack values

`src/lib/registry.pkl` is the one place a value lives when two stacks read it: host
inventory (`endpoint.hostGroup`), service endpoints at container/host/proxy level
(`endpoint.serviceGroup`), shared networks (`network.shared`), shared directories (`dir`),
Infisical address and project ids (`infisical`). Stacks reference entries by key so a typo
fails at eval.

Decisions and their reasons live in `logs/ADRs/`.
