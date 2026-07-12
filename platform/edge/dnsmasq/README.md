# dnsmasq
Central static DNS + emergency-fallback resolver for a single host's containers. Answers the host names from the registry authoritatively (`addn-hosts`) and forwards everything else to the upstreams in `DNS1`/`DNS2`. Point the host's Docker daemon at it (`daemon.json` `"dns": ["<docker0-ip>"]`) so every container on the host resolves through it — then a name change is one registry edit + re-render + SIGHUP, with **no downstream container redeploy**.

`files/hosts` is **generated** from `registry.libsonnet` (`server.hosts`) by `files/hosts.jsonnet` — the registry is the single source of truth for host → IP. Don't edit `files/hosts` by hand. This also means the tailnet host names still resolve to their IPs if Tailscale MagicDNS is ever down.

## Deploy
- No secrets.
- Publishes host `53/tcp` + `53/udp` — the host must have port 53 free. If it runs `systemd-resolved`, disable/relocate it first (infra.ansible), same idea as Traefik's `:22` prerequisite.
- Set upstreams in `compose.jsonnet`: `DNS1` = this network's primary resolver, `DNS2` = a public fallback so names still resolve if the primary is down (`strict-order` tries them in that order). `DNS1` ships as a placeholder — set it before deploying.
- Register with the daemon so containers use it: add `"dns": ["172.17.0.1"]` (this host's `docker0` gateway) to `/etc/docker/daemon.json` and restart dockerd. New containers inherit it; running containers pick it up on recreate.
- Version pinned via `local version` in `compose.jsonnet` — bump there and re-render, don't edit the generated YAML.

## Update DNS without redeploying
1. Edit `server.hosts` in `.jsonnet/lib/registry.libsonnet` (add/rename/re-IP a host). For a one-off entry not tied to the inventory, add it to the `extra` list in `files/hosts.jsonnet`.
2. Re-render: `./.jsonnet/render.py platform/edge/dnsmasq/files/hosts.jsonnet` (or just commit — lefthook re-renders on any lib change).
3. Get the new `files/hosts` onto the host and `docker kill -s HUP dnsmasq_app` — dnsmasq re-reads the file; every container sees the change on its next lookup. No downstream redeploy.

These records are authoritative (they win over upstream) and resolve even when upstream DNS is down — this is the emergency fallback. Put only names you want permanently pinned here, since a static entry overrides the real DNS answer at all times, not just during an outage.
