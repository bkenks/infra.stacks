// dnsmasq — central static DNS + emergency-fallback resolver for one host's containers.
// Names in ./files/hosts are answered authoritatively (addn-hosts); everything else forwards
// to the upstreams in DNS1/DNS2 (strict-order: primary first, public fallback second).
// Point the host's Docker daemon at this container (daemon.json `dns`) so every container
// resolves through it — then a DNS change is one edit to ./files/hosts + a SIGHUP, with no
// downstream container redeploy. See README.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'dnsmasq';
local version = '2.93';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'dockurr/dnsmasq:' + version,
      environment: {
        TZ: 'America/New_York',
        // Upstreams, tried in order (strict-order in files/fallback.conf).
        DNS1: '1.1.1.1',  // TODO(deploy): set to this network's primary resolver
        DNS2: '1.0.0.1',  // public fallback so names still resolve if the primary is down
      },
      // Published on the docker0 gateway only (not 0.0.0.0), so the host's containers reach
      // it via daemon.json `dns: [172.17.0.1]`. Binding a specific IP dodges systemd-resolved's
      // 127.0.0.53:53 — the two coexist, so NO host prep / no disabling resolved. The host
      // itself keeps resolving through resolved; containers resolve through dnsmasq. See README.
      // (If a host runs a custom Docker `bip`, set this IP + daemon.json `dns` to that gateway.)
      ports: ['172.17.0.1:53:53/tcp', '172.17.0.1:53:53/udp'],
      cap_add: ['NET_ADMIN', 'NET_RAW'],  // per dockurr/dnsmasq docs
      mounts_:: [
        // Extra directives layered onto the image's default config (conf-dir=/etc/dnsmasq.d).
        './files/fallback.conf:/etc/dnsmasq.d/fallback.conf:ro',
        // The central, live-updatable record set. SIGHUP the container to reload it.
        './files/hosts:/etc/dnsmasq/hosts:ro',
      ],
      healthcheck: {
        // Resolves a sentinel that only exists in files/hosts — proves dnsmasq is up AND
        // reading the fallback file. (busybox nslookup ships in the alpine-based image.)
        test: ['CMD', 'nslookup', 'health.check.dnsmasq', '127.0.0.1'],
        interval: '30s',
        timeout: '5s',
        retries: 3,
        start_period: '10s',
      },
    },
  }),
)
