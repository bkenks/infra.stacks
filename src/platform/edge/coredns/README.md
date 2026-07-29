# coredns

Internal split-horizon DNS. Serves the `internal.` zone from `config/internal.zone`,
forwards `ts.net` to Tailscale's resolver (`100.100.100.100`), and falls back to
`1.1.1.1`/`9.9.9.9` for everything else. Reached at `10.200.0.53` on the dedicated
`coredns` bridge (`10.200.0.0/24`) — no loopback-bound port, since a resolver is dialed
directly by IP, not proxied.

Source of truth: `stack.jsonnet` — don't edit the generated YAML (renders both
`compose.yaml` and `stack.services.yaml`).

## Deploy

**Not deployed via Komodo** — no entry in `komodo-config-sync.toml`. Deploy manually
per host with `docker compose -f compose.yaml up -d` from this directory. No
secrets, no env file.

`.nodeploy/compose.example.yaml` is an earlier hand-written sketch, kept for reference —
not used by the render pipeline or by `docker compose`.

Gotchas:
- `config/internal.zone`'s `ns` A record and this stack's `dnsIp` local must agree
  (`10.200.0.53`); bump the zone's serial on every edit or resolvers won't see changes.
- Add new LAN hosts/aliases to `config/internal.zone`, not to `stack.jsonnet` — it's
  hot-reloaded every 10s (`reload 10s` in `config/Corefile`).
