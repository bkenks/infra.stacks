# komodo-mcp

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: what it runs and its secret/deploy specifics.

Runs [MP-Tool's Komodo MCP Server](https://github.com/MP-Tool/komodo-mcp-server) — a Model Context Protocol server that exposes Komodo (servers, stacks, deployments, builds, repos, procedures, terminals, …) to MCP clients like Claude Code. Streamable-HTTP transport, reached at **`https://komodo-mcp.ktbinternal.com/mcp`** (tailnet/LAN-only, wildcard `*.ktbinternal.com` cert). Runs on **littlebuddy** alongside Komodo Core.

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to `compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Image

Pinned to `fj.ktbinternal.com/bkenks/komodo-mcp-server:1.4.1` (self-hosted Forgejo mirror of the upstream `MP-Tool/komodo-mcp-server` project, tracking its release tags). **Verify the `1.4.1` tag exists on the mirror before deploying** — e.g. via the Forgejo package UI or `docker manifest inspect fj.ktbinternal.com/bkenks/komodo-mcp-server:1.4.1`. If it doesn't exist yet, the mirror needs to sync the tag first.

### Security

The MCP HTTP endpoint has **no built-in authentication** and the configured Komodo key is **full read/write** (deploy / execute / terminal across the fleet). Two layers protect it:

1. **Exposure:** `*.ktbinternal.com` is internal-only — no inbound ports, reachable only over LAN + Tailscale.
2. **Traefik basic-auth:** the `komodo-mcp-auth` middleware (htpasswd users in `KOMODO_MCP_BASICAUTH_USERS`) guards the route. MCP clients must send an `Authorization: Basic …` header.

To dial this back, issue a read-only Komodo API key instead and re-render the secret — no compose change needed.

### Secrets

Secrets are NOT stored in this repo. The Infisical agent renders them to the host and this stack pulls them in — how that works → Notion: [Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd).

This stack's specifics:
- Store each secret in Infisical under the `/komodo-mcp` folder (registry: `.jsonnet/lib/registry.libsonnet` → `agentServices.'komodo-mcp'`):
  - `KOMODO_API_KEY` / `KOMODO_API_SECRET` — a Komodo service-account API key (Komodo UI → Settings → API Keys), full read/write.
  - `KOMODO_MCP_BASICAUTH_USERS` — Traefik basic-auth htpasswd string, e.g. `htpasswd -nbB brian 'somepass'` → `brian:$2y$05$…` (store the whole `user:hash`). The plaintext password goes in the MCP client's `Authorization: Basic` header.
- The agent renders them to `/dev/shm/komodo-mcp.env` on the **same host**. `compose.jsonnet`'s `include.env_file` pulls it in.

Non-secret config (transport, Komodo URL, allowed hosts, timezone) is baked directly into `compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

### Connecting Claude Code

```bash
# user:pass base64 = printf 'brian:somepass' | base64
claude mcp add --transport http komodo https://komodo-mcp.ktbinternal.com/mcp \
  --header "Authorization: Basic <base64-of-user:pass>"
```

### Compose Commands

*Start Stack (local/standalone testing only — in the homelab deploy via Komodo):*
```bash
docker compose up -d
```
