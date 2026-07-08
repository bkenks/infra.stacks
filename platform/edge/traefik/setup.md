# Traefik — per-host reverse proxy
Per-host reverse proxy — routes to any container labelled `traefik.enable=true` on the shared `proxy` network. Dashboard: `https://traefik.ktbinternal.com`.

TLS: `websecure` (443) serves Cloudflare DNS-01 wildcard certs (Let's Encrypt) — no per-service certs. Every host requests every wildcard, so any host can terminate TLS for any service. See `files/traefik.yml` (static config) and `files/host.yml` (shared dynamic config, identical on every host).

## Deploy

- Secrets: `CF_DNS_API_TOKEN` (DNS-01 ACME, lego cloudflare provider) — tier-0 bootstrap secret, supplied via host env, never committed. Every host requests **all** zones, so every host's token must be scoped Zone:DNS:Edit + Zone:Read on **`ktbinternal.com` + `stackform.app` + `couchpotatoes.store`** (same Cloudflare account, one token). QUIRK: a host with a narrower token still serves what it can but spams DNS-01 failures for the rest (LE rate-limit risk) — widen the token before deploying.
- Order on a new host: (1) `proxy` network created by `infra.ansible` at provisioning, (2) deploy Komodo (`stack.infra/komodo`), (3) deploy this stack.
- `files/host.yml` / `files/controller/controller.yaml` changes are **not** auto-redeployed — redeploy from Komodo on each host after pushing.

## Expose a service

```yaml
    networks: [default, proxy]      # default = its own deps; proxy = Traefik
    labels:
      traefik.enable: 'true'
      traefik.http.routers.<name>.rule: 'Host(`<name>.ktbinternal.com`)'
      traefik.http.routers.<name>.entrypoints: websecure
      traefik.http.routers.<name>.tls: 'true'
      traefik.http.services.<name>.loadbalancer.server.port: '<container-port>'
```

…and declare `proxy: {external: true}` in that stack's `networks:`. Only Traefik publishes 80/443.

## Central controller (single front router)

Every host runs in controller mode: `files/controller/controller.yaml` (mounted on every host) is the service→host map — `*.ktbinternal.com` DNS just points at one host, and that host's copy of the table becomes the live router (no role flag).

QUIRK: table routers are `priority: 1` (lowest), so a service running locally is always served by its own docker-label router first — only remote services fall through to the table. Backends re-encrypt over each host's own valid `*.ktbinternal.com` ACME cert (verified, no `insecureSkipVerify`) — every host must keep that cert.

**Promote a host:** point `*.ktbinternal.com` DNS at it — no redeploy needed. **Add/move a service:** edit `controller.yaml` (`rule:` = public name, `service:` = backend host).

Edge case: if DNS points at a host whose local copy of that service is down, the table re-encrypts to itself → brief self-loop until timeout (rare; no worse than a 404).
