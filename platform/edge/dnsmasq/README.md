# dnsmasq
Central static DNS + emergency-fallback resolver for a single host's containers. Answers the names in `files/hosts` authoritatively (`addn-hosts`) and forwards everything else to the upstreams in `DNS1`/`DNS2`. Point the host's Docker daemon at it (`daemon.json` `"dns": ["<docker0-ip>"]`) so every container on the host resolves through it — then a name change is one edit to `files/hosts` plus a SIGHUP, with **no downstream container redeploy**.

## Deploy
- No secrets.
- Publishes host `53/tcp` + `53/udp` — the host must have port 53 free. If it runs `systemd-resolved`, disable/relocate it first (infra.ansible), same idea as Traefik's `:22` prerequisite.
- Set upstreams in `compose.jsonnet`: `DNS1` = this network's primary resolver, `DNS2` = a public fallback so names still resolve if the primary is down (`strict-order` tries them in that order). `DNS1` ships as a placeholder — set it before deploying.
- Register with the daemon so containers use it: add `"dns": ["172.17.0.1"]` (this host's `docker0` gateway) to `/etc/docker/daemon.json` and restart dockerd. New containers inherit it; running containers pick it up on recreate.
- Version pinned via `local version` in `compose.jsonnet` — bump there and re-render, don't edit the generated YAML.

## Update DNS without redeploying
1. Edit `files/hosts` (standard `IP  name` format).
2. `docker kill -s HUP dnsmasq_app` — dnsmasq re-reads the file; every container sees the change on its next lookup.

`files/hosts` records are authoritative (they win over upstream) and resolve even when upstream DNS is down — this is the emergency fallback. Put only names you want permanently pinned here, since a static entry overrides the real DNS answer at all times, not just during an outage.
