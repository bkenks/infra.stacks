# infisical-agent

Renders each host's stack secrets from Infisical to `/dev/shm/<stack>.env` (RAM, never disk). Each consumer stack pulls its file in via the compose `include: -> env_file:` convention. Split out of the `infisical` server stack so it can run on **every** host while the server runs on only one.

Runs in one of two profiles — **`init`** (Ansible, control-plane only, one-shot, renders tier-0 secrets during cold bootstrap) and **`standard`** (Komodo, every host, long-running). The profile model, why `init` exists, and how periphery PKI auth means subservers need no Infisical secrets are all documented in Notion:

> 📚 **Notion → [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd)** → "The agent: `init` vs `standard` profiles". (Notion = prose/architecture; this README = config/usage.)

## Per-host config

The **standard** profile selects a per-host config: `AGENT_HOST` → `files/configs/<host>.yaml`. The **init** profile uses the fixed, host-agnostic `files/configs/control-plane.bootstrap.yaml` (set via `AGENT_CONFIG_NAME` in `compose/init.yml`); `AGENT_HOST` there only carries the real host name for the `${AGENT_HOST}` secret-path substitution. Each host gets its **own machine identity**, scoped in Infisical to only that host's secret folders — so a host's identity and its config both only ever touch its own stacks.

Add a host: create `files/configs/<host>.yaml`, create a scoped machine identity in Infisical, then deploy the `standard` profile from Komodo with per-server vars `AGENT_HOST=<host>`, `INFISICAL_CLIENT_ID=…`, `INFISICAL_CLIENT_SECRET=…`.

## Templates — one shared file per stack

Each stack's render template lives in **exactly one file** under `files/configs/templates/<stack>.tpl` (Go `text/template`). Host configs never inline a `template-content:` body — they reference the shared file via `source-path` and supply only the per-host `destination-path` (and `config:`):

```yaml
templates:
  - source-path: /agent-templates/komodo_core.tpl
    destination-path: /dev/shm/komodo_core.env
    config:
      polling-interval: "1m"
```

This means a stack's template body is defined once and reused across every host that runs it. **To move a stack between hosts, move its `source-path` block** — never copy the template. The `init` and `standard` profiles share the same `.tpl` files; only `destination-path` differs between them.

**`${AGENT_HOST}` substitution.** The Infisical agent's template engine has no access to the environment, so host-specific secret paths (e.g. cloudflared's `/hosts/<host>/cloudflared`) can't be expressed in a template directly. `entrypoint.sh` bridges this: it copies `files/configs/templates/*.tpl` (mounted at `/agent-configs/templates`) to a writable `/agent-templates/`, substituting the literal `${AGENT_HOST}` with the host name — the only substitution performed; secret *values* are still fetched by the agent at render time. Configs therefore point `source-path` at `/agent-templates/<stack>.tpl`, not the read-only original. Templates without the placeholder are copied through unchanged.

Add a consumer to a host: add a `source-path` block to that host's config pointing at the shared `.tpl` (create the `.tpl` if the stack is new), store the stack's secrets in Infisical under `/<stack>` (`APPNAME_SECRETNAME` convention), and scope the host's machine identity to read that folder.

## Deploy

```bash
# init (control-plane bootstrap) — via Ansible:
ansible-playbook playbooks/deploy.yml --tags infisical-agent   # writes creds to /dev/shm, runs the init profile

# standard — via Komodo: deploy this stack with COMPOSE_PROFILES=standard and the
# per-server variables above.
```

Machine-identity creds are never committed — they come from Ansible (`/dev/shm`) or Komodo per-server variables at runtime, and the secret file is wiped on read (`remove_client_secret_on_read`).
