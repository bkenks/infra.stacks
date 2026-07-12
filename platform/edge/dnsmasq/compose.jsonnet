// dnsmasq — central static DNS + emergency-fallback resolver for one host's containers.
// Names in ./files/hosts are answered authoritatively (addn-hosts); everything else forwards
// to the upstreams in DNS1/DNS2 (strict-order: primary first, public fallback second).
// Point the host's Docker daemon at this container (daemon.json `dns`) so every container
// resolves through it — then a DNS change is one edit to ./files/hosts + a SIGHUP, with no
// downstream container redeploy. See README.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local roles = reg.roles;

local stack = 'dnsmasq';
local s = c.stack(stack);
local n = s.names;
local version = '2.93';

local manifest = {
  name: stack,

  services: {
    [roles.app]: {
      local extName = n.container(roles.app),

      image: 'dockurr/dnsmasq:' + version,
      container_name: extName,
      restart: 'unless-stopped',
      environment: {
        TZ: 'America/New_York',
        // Upstreams, tried in order (strict-order in files/fallback.conf).
        DNS1: '1.1.1.1',  // TODO(deploy): set to this network's primary resolver
        DNS2: '1.0.0.1',  // public fallback so names still resolve if the primary is down
      },
      // Host-published so the Docker daemon (daemon.json `dns`) and the host resolve through
      // it. Requires port 53 free on the host — see README (systemd-resolved prerequisite).
      ports: ['53:53/tcp', '53:53/udp'],
      cap_add: ['NET_ADMIN', 'NET_RAW'],  // per dockurr/dnsmasq docs
      volumes: [
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
  },

  networks: s.network.default,  // no peers — reached via published host port 53
};

c.render(stack, manifest)
