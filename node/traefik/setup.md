# Traefik — per-host reverse proxy

> 📚 System architecture, secrets-flow, and security notes live in Notion → [Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c). This file covers only `traefik`: how to deploy/use it and its quirks. (Notion = prose/architecture; repo = compose/usage.)

Traefik is the per-host reverse proxy on each host. It
routes to any container labelled `traefik.enable=true` on the shared `proxy`
network.

TLS: `websecure` (443) serves Cloudflare DNS-01 wildcard certs (Let's Encrypt
ACME) — no per-service certs. **Which** wildcards a host requests is per-host
config (see below): every host gets `*.homektb.com`; `maboi` also gets
`*.stackform.app` and `*.couchpotatoes.store`. See `files/traefik.yml` (static
config) and `files/configs/<host>.yml` (per-host dynamic config).

## Per-host config

Like the `infisical-agent` stack, this stack is the **same** for every host and
selects a per-host config file by the `AGENT_HOST` Komodo per-server variable
(the one already set on each host — no new variable needed):

`AGENT_HOST` → `files/configs/<host>.yml`, mounted into the container at
`/etc/traefik/dynamic/host.yml` and loaded by Traefik's `file` provider. Each
host's file defines the Traefik dashboard router and the **ACME cert domains that
host requests**:

| Host          | Cert domains requested |
|---------------|------------------------|
| `littlebuddy` | `*.homektb.com` |
| `paiki`       | `*.homektb.com` |
| `maboi`       | `*.homektb.com`, `*.stackform.app`, `*.couchpotatoes.store` |

The compose volume mount uses `${AGENT_HOST:?…}`, so a deploy with `AGENT_HOST`
unset **fails loudly** rather than starting with no dynamic config.

**Add a host:** copy `files/configs/paiki.yml` (the homektb-only template) to
`files/configs/<host>.yml`, add any extra zones it needs, then deploy this stack
from Komodo on that host (its per-server `AGENT_HOST` selects the file). Traefik
config changes are **not** auto-redeployed (the
`redeploy-infisical-agents` workflow is path-filtered to the agent's configs) —
redeploy the Traefik stack from Komodo after pushing.

## Secrets

Traefik needs the Cloudflare API token (`CF_DNS_API_TOKEN`) for the DNS-01 ACME
challenge — the lego cloudflare provider reads it from the container environment
(see `files/traefik.yml`). It must be scoped Zone:DNS:Edit + Zone:Read on **every
zone the host's per-host file requests** (so `maboi`'s token also needs
`stackform.app` + `couchpotatoes.store`, which must be in the **same** Cloudflare
account as `homektb.com` — one token). As a tier-0 bootstrap secret it is never
committed to git; it's supplied via the host's secret env, not baked into the
image.

## How a service gets exposed

Add to the service in its own stack (see `infisical/compose/stack.yml`):

```yaml
    networks: [default, proxy]      # default = its own deps; proxy = Traefik
    labels:
      traefik.enable: 'true'
      traefik.http.routers.<name>.rule: 'Host(`<name>.homektb.com`)'
      traefik.http.routers.<name>.entrypoints: websecure
      traefik.http.routers.<name>.tls: 'true'
      traefik.http.services.<name>.loadbalancer.server.port: '<container-port>'
```

…and declare the external network at the bottom of that stack:

```yaml
networks:
  proxy:
    external: true
```

Only Traefik publishes 80/443 — apps need no published host port.

## One-time setup (per host)

The shared `proxy` network is created by **Ansible** (`infra.ansible`) during host
provisioning — not by this stack. Traefik **and** Komodo both attach to it, and
Traefik proxies the Komodo UI, so bring a host up in this order:

1. **Create the `proxy` network** — done by `infra.ansible` when the host is
   provisioned (an external Docker network that Komodo and Traefik both join).
2. **Deploy Komodo** (`stack.infra/komodo`) — the orchestrator Traefik routes to.
3. **Deploy this Traefik stack** — it attaches to the existing `proxy` network and
   starts routing (Komodo UI, Infisical, and every app stack).

## Access

Point `*.homektb.com` (or a hosts entry) at the host, then hit
`https://infisical.homektb.com` (valid Cloudflare wildcard TLS — no cert warning).
Dashboard: `https://traefik.homektb.com`.
