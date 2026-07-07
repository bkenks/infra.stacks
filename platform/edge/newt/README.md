# newt

> 📚 The edge/ingress model (per-host Traefik, wildcard TLS, the secrets-flow) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `platform/edge/newt`: how to run it and its quirks.

Pangolin **site** connector ([`fosrl/newt`](https://github.com/fosrl/newt)). Dials out to the Pangolin control server (`PANGOLIN_ENDPOINT=https://pangolin.homektb.com`), registers this host as a site, and forwards inbound tunnel traffic to the host's Traefik. It joins the host's `shared-proxy` bridge so tunnel targets can reach Traefik by name (`https://traefik:443`) — the same shape as [`cloudflared`](../cloudflared/README.md), just a different upstream.

## Role-scoped secret (the point of this stack)

`NEWT_ID` / `NEWT_SECRET` are rendered to `/dev/shm/newt.env` by the Infisical agent from a **role-scoped** folder:

| | folder | scope |
|---|---|---|
| `cloudflared` | `/hosts/${AGENT_HOST}/cloudflared` | per **host** |
| **`newt`** | `/roles/traefik-controller` | per **role** |

This is the deliberate move away from binding services to hosts: the credentials live under the `traefik-controller` role, so any host that adopts that role (opts the `newt` service into its `AGENT_SERVICES`) pulls the same site credentials — servers can swap the role without re-homing secrets. See `.jsonnet/lib/registry.libsonnet` → `agentServices.newt`.

## Prerequisites

1. **Infisical** — in the `infra` project, create folder `/roles/traefik-controller` (env `prod`) with secrets `NEWT_ID` and `NEWT_SECRET` (from Pangolin → Sites → create site). See `.env.example`.
2. **Host** — must run the Infisical agent with `newt` in its `AGENT_SERVICES`, and own a `shared-proxy` network (i.e. run `platform/edge/traefik`). Do **not** run this on the dedicated Pangolin VPS (`platform/edge/pangolin` already terminates ingress there).

## Notes

- Image is pinned to `fosrl/newt:1.14.0` (the `version` local in `compose.stack.jsonnet`); bump it there and re-render, don't edit the YAML.
- Single outbound service — no ports published, no private-net peers.
