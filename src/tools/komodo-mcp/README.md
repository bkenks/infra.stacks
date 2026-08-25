# komodo-mcp

Runs [MP-Tool's Komodo MCP Server](https://github.com/MP-Tool/komodo-mcp-server), exposing Komodo to MCP clients like Claude Code. Streamable-HTTP at **https://komodo-mcp.ktbinternal.com/mcp** (tailnet/LAN-only). Runs on **littlebuddy** alongside Komodo Core.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml` / `services.yaml`.

## Deploy

Deployed via Komodo. Pinned to `fj.ktbinternal.com/bkenks/komodo-mcp-server:1.4.1` (self-hosted mirror) — verify the tag exists on the mirror before deploying (`docker manifest inspect fj.ktbinternal.com/bkenks/komodo-mcp-server:1.4.1`).

Infisical `/komodo-mcp` (`KOMODO_API_KEY`, `KOMODO_API_SECRET`, `KOMODO_MCP_BASICAUTH_USERS`) → `/dev/shm/komodo-mcp.env`. `KOMODO_MCP_BASICAUTH_USERS` is a htpasswd string (`htpasswd -nbB user pass` → `user:hash`); the plaintext password goes in the MCP client's `Authorization: Basic` header.

The configured Komodo key is full read/write and the endpoint has no built-in auth — protected only by network exposure (LAN/tailnet-only) and the Traefik `komodo-mcp-auth` basic-auth middleware. To restrict, issue a read-only Komodo API key instead.

Connect Claude Code:
```bash
claude mcp add --transport http komodo https://komodo-mcp.ktbinternal.com/mcp \
  --header "Authorization: Basic <base64-of-user:pass>"
```
