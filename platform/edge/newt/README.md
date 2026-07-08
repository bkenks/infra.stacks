# newt

> 📚 The edge/ingress model (per-host Traefik, wildcard TLS, the secrets-flow) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `platform/edge/newt`: how to run it and its quirks.

Pangolin **site** connector ([`fosrl/newt`](https://github.com/fosrl/newt)). Dials out to the Pangolin control server (`PANGOLIN_ENDPOINT=https://pangolin.ktbinternal.com`), registers this host as a site, and forwards inbound tunnel traffic to the host's Traefik. It joins the host's `shared-proxy` bridge so tunnel targets can reach Traefik by name (`https://traefik:443`) — the same shape as [`cloudflared`](../cloudflared/README.md), just a different upstream.

## Host-scoped secret

`NEWT_ID` / `NEWT_SECRET` are rendered to `/dev/shm/newt.env` by the Infisical agent from a **per-host** folder, exactly like `cloudflared` — the folder is keyed on `${AGENT_HOST}`, so each host gets its own Pangolin site credentials:

| | folder |
|---|---|
| `cloudflared` | `/hosts/${AGENT_HOST}/cloudflared` |
| **`newt`** | `/hosts/${AGENT_HOST}/newt` |

`${AGENT_HOST}` is resolved at runtime by the agent's `entrypoint.sh` (a `sed` sub over the fragment) from the host's own `infisical-agent_<host>` stack. See `.jsonnet/lib/registry.libsonnet` → `agentServices.newt`.

## Prerequisites

1. **Infisical** — in the `infra` project, create folder `/hosts/<host>/newt` (env `prod`) with secrets `NEWT_ID` and `NEWT_SECRET` (from Pangolin → Sites → create site), for each host that will run newt. See `.env.example`.
2. **Host's Infisical agent** — add `newt` to that host's `infisical-agent_<host>` stack's `AGENT_SERVICES`.
3. **Host** — must own a `shared-proxy` network (i.e. run `platform/edge/traefik`). Do **not** run this on the dedicated Pangolin VPS (`platform/edge/pangolin` already terminates ingress there).

## Notes

- Image is pinned to `fosrl/newt:1.14.0` (the `version` local in `compose.stack.jsonnet`); bump it there and re-render, don't edit the YAML.
- Single outbound service — no ports published, no private-net peers.
