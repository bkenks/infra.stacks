# Traefik — per-host reverse proxy

> 📚 System architecture, secrets-flow, and security notes live in Notion → [Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c). This file covers only `traefik`: how to deploy/use it and its quirks. (Notion = prose/architecture; repo = compose/usage.)

Traefik is the per-host reverse proxy on each host. It
routes to any container labelled `traefik.enable=true` on the shared `proxy`
network.

TLS: `websecure` (443) serves Cloudflare DNS-01 wildcard certs (Let's Encrypt
ACME) — no per-service certs. **Every host requests every wildcard** (see below),
so any host can terminate TLS for any service. See `files/traefik.yml` (static
config) and `files/host.yml` (the shared dynamic config).

## Shared dynamic config

The platform is stateless/portable — any app can run on any host and lift-and-shift
freely. So this stack mounts **one identical file on every host**:
`files/host.yml` → `/etc/traefik/dynamic/host.yml`, loaded by Traefik's `file`
provider. (No `AGENT_HOST` selection — that variable is no longer used by this
stack.) It defines the dashboard router (`traefik.homektb.com`) and the **ACME
cert domains every host requests**:

| Zone                 | Wildcards |
|----------------------|-----------|
| `homektb.com`        | `*.homektb.com` + the dotted per-host `*.lilbud/paiki/maboi/bill.homektb.com` (still used by apps not yet on single-label — the media stack is dotted-only). All in the `homektb.com` zone, so no extra token scope. |
| `stackform.app`      | `*.stackform.app` |
| `couchpotatoes.store`| `*.couchpotatoes.store` |

Retire a dotted `*.<host>.homektb.com` wildcard once every app under it has moved
to a single-label router. Traefik config changes are **not** auto-redeployed —
redeploy the Traefik stack from Komodo on each host after pushing.

## Secrets

Traefik needs the Cloudflare API token (`CF_DNS_API_TOKEN`) for the DNS-01 ACME
challenge — the lego cloudflare provider reads it from the container environment
(see `files/traefik.yml`). Because every host now requests **all** zones, every
host's token must be scoped Zone:DNS:Edit + Zone:Read on **`homektb.com` +
`stackform.app` + `couchpotatoes.store`** (all in the **same** Cloudflare account
— one token). A host whose token lacks a zone still serves the zones it can but
spams DNS-01 failures for the rest (LE rate-limit risk) — widen the token before
deploying. As a tier-0 bootstrap secret it is never committed to git; it's
supplied via the host's secret env, not baked into the image.

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

## Central controller role (single front router)

This same stack also acts as the **one central router** in front of all the
other hosts, so `*.homektb.com` points at a single host and routing to the right
host is done here — not in DNS. **Every host runs in controller mode:** the
central routing table (`files/controller/controller.yml`) is mounted on every
host at `/etc/traefik/dynamic/controller.yml`. There is no role flag — whichever
host `*.homektb.com` DNS points at *is* the active router.

**How it works.** The table's routers are **`priority: 1`** (lowest), so on any
host a service that runs *locally* is still served by its own docker-label router
(higher default priority) — only **remote** services fall through to the table.
A host that DNS isn't pointed at never receives these `Host()` requests, so its
copy of the table sits **dormant** — harmless. No loops, and **app labels never
change**. Backends re-encrypt to each host's `:443` over a **verified** TLS
connection: each host already serves its publicly-trusted Let's Encrypt
`*.homektb.com` wildcard, so the router validates it against the system CA roots
(via a `serverName` the wildcard covers, since we dial raw Tailscale IPs) — no
`insecureSkipVerify`. This means each host must **keep** its ACME `*.homektb.com`
cert (don't switch hosts to a self-signed cert). Every host already holds the
`*.homektb.com` wildcard and the `CF_DNS_API_TOKEN` (via `node_traefik.env`), so
**no new cert or secret**.

> **Edge case:** if a service's container is *down* **and** DNS points at that
> same host, its local docker router disappears, the table router matches and
> re-encrypts to itself → a short self-loop until timeout. Rare (down service +
> DNS on its own host); no worse than a 404 in practice.

**Promote a host to the active router:** point the `*.homektb.com` wildcard DNS
(and/or the cloudflared wildcard ingress) at it. That's it — no redeploy, no flag,
since every host already carries the table.

**The service → host map** lives in `files/controller/controller.yml` — one router
entry per single-label service (`rule:` = its public name, `service:` = the host
backend that runs it). This is the only place the "which host" knowledge lives
(it replaces per-service DNS records). Add a line when a service is added; change
`service:` when one moves hosts. The seed entries there must be verified/extended
against the real inventory. Host backends (Tailscale IPs) are identical on every
host, so the file is portable as-is.
