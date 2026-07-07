# newt

> 📚 The edge/ingress model (per-host Traefik, wildcard TLS, the secrets-flow) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `platform/edge/newt`: how to run it and its quirks.

Pangolin **site** connector ([`fosrl/newt`](https://github.com/fosrl/newt)). Dials out to the Pangolin control server (`PANGOLIN_ENDPOINT=https://pangolin.homektb.com`), registers this host as a site, and forwards inbound tunnel traffic to the host's Traefik. It joins the host's `shared-proxy` bridge so tunnel targets can reach Traefik by name (`https://traefik:443`) — the same shape as [`cloudflared`](../cloudflared/README.md), just a different upstream.

## Role-scoped secret (the point of this stack)

`NEWT_ID` / `NEWT_SECRET` are rendered to `/dev/shm/newt.env` by the Infisical agent from a **role-scoped** folder. It's the exact mirror of `cloudflared`, except the folder is parameterized by the host's *role* (`${AGENT_ROLE}`) instead of its *host name* (`${AGENT_HOST}`):

| | folder | parameterized by |
|---|---|---|
| `cloudflared` | `/hosts/${AGENT_HOST}/cloudflared` | `AGENT_HOST` (per host) |
| **`newt`** | `/roles/${AGENT_ROLE}/newt` | `AGENT_ROLE` (per role) |

Both are resolved at runtime by the Infisical agent's `entrypoint.sh` (a `sed` sub over the fragment), so there is one registry entry and one template — the value of `AGENT_ROLE` selects the folder. This is the deliberate move away from binding services to hosts: a host running the `traefik-controller` role sets `AGENT_ROLE=traefik-controller` and the agent dumps `/roles/traefik-controller/newt`. Swap a server's role and it pulls a different folder — no per-host secret paths. See `.jsonnet/lib/registry.libsonnet` → `agentServices.newt`.

## Prerequisites

1. **Infisical** — in the `infra` project, create folder `/roles/traefik-controller/newt` (env `prod`) with secrets `NEWT_ID` and `NEWT_SECRET` (from Pangolin → Sites → create site). See `.env.example`. (The machine identity of any host in this role must be scoped to read `/roles/traefik-controller/*`.)
2. **Host's Infisical agent** — the host's `infisical-agent_<host>` Komodo stack must set `AGENT_ROLE=traefik-controller` and include `newt` in its `AGENT_SERVICES`.
3. **Host** — must own a `shared-proxy` network (i.e. run `platform/edge/traefik`). Do **not** run this on the dedicated Pangolin VPS (`platform/edge/pangolin` already terminates ingress there).

## Notes

- Image is pinned to `fosrl/newt:1.14.0` (the `version` local in `compose.stack.jsonnet`); bump it there and re-render, don't edit the YAML.
- Single outbound service — no ports published, no private-net peers.
