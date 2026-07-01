# .template — scaffold a new stack

This directory is not a real stack — it's what you copy to start one. Every
stack in this repo compiles from jsonnet (`.jsonnet/lib/*.libsonnet`) to the
YAML `docker compose` actually reads; nothing here is hand-edited YAML.

### Worked examples

Copy patterns from real, validated stacks rather than guessing:

- `apps/business/docuseal` — simple, single-service, joins shared-postgres.
- `apps/personal/paperless` or `apps/business/openproject` — multi-service.
- `tools/termix` — multi-service, no secrets, one internal-only sidecar.

### Steps

1. **Copy this directory** to the new stack's location, e.g.:
   ```bash
   cp -r .template apps/personal/mystack
   ```

2. **Rename the jsonnet locals.** In both `compose.jsonnet` and
   `compose.stack.jsonnet`, set `stack` to the real stack name (keep it in
   sync across both files — it's the Compose project name, the Docker network
   name, and the `<stack>-<role>` prefix for containers/volumes/aliases). In
   `compose.stack.jsonnet`, set `image`, `version`, and `port` to the real
   values.

3. **Decide which shared networks this stack needs**, and delete what you
   don't use from `compose.stack.jsonnet`:
   - **shared-proxy** (Traefik) — keep if the service is reached over the
     web. Uses `lib.compose.join('proxy')` in `networks:` plus
     `lib.mixins.proxyAdd(stack, stack, port)` in `labels:`. Drop both (and
     the network-join under `networks:`) for an internal-only service (see
     `guacd` in `tools/termix/compose.stack.jsonnet`).
   - **shared-postgres** — keep if the stack has its own DB there. Uses
     `lib.compose.join('postgres')` plus
     `lib.compose.endpoint('postgres').private.host` /`.port` to build the
     connection string. Delete the `pgHost`/`pgPort` locals, the network
     join, and `DATABASE_URL` if there's no DB.
   - Other shared nets/endpoints follow the same `lib.compose.join(...)` /
     `lib.compose.endpoint(...)` pattern — see `.jsonnet/lib/registry.libsonnet`
     `sharedNetworks` / `endpoints` for what's available.
   - **Named volumes** — declare one with `n.volume('<role>')` used both in
     the service's `volumes:` mount and the top-level `volumes:` block (as
     shown for `data` in `compose.stack.jsonnet`). This gives the volume an
     explicit name instead of Docker's implicit `<project>_<service>` one.

4. **If the stack has secrets**, add an entry to `agentServices` in
   `.jsonnet/lib/registry.libsonnet` (the Infisical agent's secret
   catalogue — see that file's own header comment for the full field
   reference):
   - `project` — key into `registry.libsonnet`'s `projects` map (which
     Infisical project the secrets live in).
   - `folder` — the Infisical secret path, e.g. `/mystack` (may contain
     `${AGENT_HOST}` for host-scoped folders).
   - `dest` — the output filename under `/dev/shm/` the agent renders to;
     must match what `compose.jsonnet`'s `include.env_file` reads.
   - `type` — `dump` (whole folder → `KEY=VALUE`, the common case),
     `map` (explicit renames via a `keys` map), or `raw` (a single secret's
     raw value, no `KEY=` prefix — for non-`KEY=VALUE` files like a `.key`
     bind mount).

   Then in `compose.stack.jsonnet`, reference each secret as
   `${VAR_NAME:?err}` inline (see `SOME_SECRET`/`DATABASE_URL` in the
   template) — never inject a whole secrets file into a container; secrets
   arrive by **interpolation**, not `env_file:` injection. Finally, uncomment
   the `env_file: ['/dev/shm/' + stack + '.env']` line in `compose.jsonnet`'s
   `include:` block. If the stack has no secrets, leave that line commented
   out (and delete any `${VAR:?err}` references from `compose.stack.jsonnet`).

5. **Render the jsonnet to YAML:**
   ```bash
   .jsonnet/render.sh compose.jsonnet
   .jsonnet/render.sh compose.stack.jsonnet
   ```
   This writes `compose.yaml` and `compose.stack.yaml` — generated,
   do-not-edit files. Re-run after every jsonnet change.

6. **Write/adapt `tests/render_compose.sh`** to fake this stack's real
   secrets (one `printf "VAR=test\n" > /dev/shm/<dest>` per `agentServices`
   entry the stack reads, matching `compose.jsonnet`'s `include.env_file`),
   then run it:
   ```bash
   tests/render_compose.sh
   tests/render_compose.sh --services   # any `docker compose config` flag passes through
   ```
   This runs `docker compose config` in a throwaway Linux container (macOS
   has no `/dev/shm`) to validate the fully merged config without touching
   the real host.

7. **Delete this README's boilerplate** and write a real one for the stack
   (what it runs, where it's reached, its secrets) — `docuseal`'s and
   `termix`'s READMEs are good length/shape references.

### Why jsonnet

Cross-stack values (shared network names, service endpoints, Infisical
project IDs, the secrets catalogue) live once in
`.jsonnet/lib/registry.libsonnet` and are referenced **by key**, not by
hand-typed string — a typo'd key fails at compile time instead of silently
producing an empty/wrong value at deploy time. `.jsonnet/lib/compose.libsonnet`
and `.jsonnet/lib/mixins.libsonnet` build on top of that registry for
consistent naming (`lib.compose.names(stack)`), network joins
(`lib.compose.join(...)`), and Traefik labels (`lib.mixins.proxyAdd(...)`).
