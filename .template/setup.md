## Stack: replaceme.STACKNAME

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

One-line description of what this stack runs and where it's reached.

### Scaffold a new stack from this template

Global search-and-replace these tokens, then rename files where noted:

| Token                  | Meaning                                              |
|------------------------|------------------------------------------------------|
| `replaceme.STACKNAME`  | stack name / Infisical secrets folder (`/<name>`)    |
| `replaceme.APPNAME`    | software name; the `container-envs/<name>.env` file  |
| `replaceme.IMAGE`      | full image ref (e.g. `docker.io/library/postgres`)   |
| `replaceme.VERSTAG`    | image version tag (pin it; avoid `latest`)           |
| `replaceme.PORT`       | internal container port to `expose`                  |
| `replaceme.SECRETFILE` | basename the agent renders, e.g. `apps_<stackname>`  |
| `REPLACEME_SECRET`     | each secret key (matches the Infisical key + agent)  |

Then:
- Rename `container-envs/app.env` to `container-envs/replaceme.APPNAME.env` and
  set `APP__NAME` in `interpolation-envs/general.env` to match.
- Add one service block (+ its `container-envs/<name>.env`, `__NAME`,
  `__VERS_TAG`, `__MAX_RESTART_ATTEMPS`) per additional service. See
  `stack.infra/gitea` (app + db) for a worked two-service example.

### Where each value goes

- **Literal, non-secret, injected into a container** → `container-envs/<name>.env`
- **Anything with `${...}` (secrets, cross-service refs)** → `compose/secrets.yml`
- **Interpolation-only vars (names, version tags, restart counts)** →
  `interpolation-envs/{general,production}.env`

This split exists because a service's `env_file:` is **not** interpolated, so
`${...}` only resolves in the compose body — see the header in
`compose/secrets.yml`.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host
and this stack pulls them in — how that works → Notion: [Bootstrapping a Host
from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd)
(the Infisical agent secrets-flow).

This stack's specifics:
- Store each secret in Infisical under the `/replaceme.STACKNAME` folder and add
  a template entry in the agent config (`stack.node/infisical-agent`).
- The agent renders them to `/dev/shm/replaceme.SECRETFILE.env` on the **same
  host**; `compose.yaml`'s `include: -> env_file:` pulls them in.

If the stack has no secrets, delete `compose/secrets.yml`, its line in
`compose.yaml`'s `path:`, and the `/dev/shm/...` `env_file:` line.

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed.)
