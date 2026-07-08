// traefik — this host's reverse proxy + TLS terminator. Owner of shared-proxy.
//
// Renders to compose.yaml — do not edit the YAML. Traefik creates shared-proxy
// (deploy it FIRST; consumers join it external). Service discovery is pinned to
// shared-proxy in files/traefik.yml (providers.docker.network) — keep in sync.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local roles = reg.roles;

local stack = 'traefik';
local s = c.stack(stack);
local n = s.names;
local version = 'v3.6.7';  // >= v3.6.1 so Docker 29 API negotiation works

local proxyNetwork = 'proxy';

{
  name: stack,

  services: {
    [roles.app]: {
      local extName = n.container(roles.app),

      image: 'docker.io/library/traefik:' + version,
      container_name: extName,
      restart: 'unless-stopped',
      // Hard memory ceiling. Without it a request spike (e.g. the controller-table
      // routing loop that froze littlebuddy 2026-06-29) can consume all host RAM.
      // With it, the cgroup OOM-kills just Traefik and restart:unless-stopped
      // brings it back — the host stays up. GOMEMLIMIT (below) keeps Go's GC
      // aggressive well under this so it rarely trips on legitimate load.
      mem_limit: '1g',
      environment: {
        TZ: 'America/New_York',
        // Keep Go's heap target below mem_limit so GC reclaims hard before the
        // cgroup OOM-kills the container.
        GOMEMLIMIT: '750MiB',
        // Secret — CF_DNS_API_TOKEN for the Cloudflare DNS-01 ACME challenge (lego
        // reads it from the container env). Interpolated from /dev/shm/platform.env
        // (parent include.env_file).
        CF_DNS_API_TOKEN: '${CF_DNS_API_TOKEN:?err}',
      },
      // Traefik owns 80/443. :22 is Forgejo git-over-SSH — needs admin sshd moved
      // off 22 first (infra.ansible), else the bind conflicts.
      ports: ['80:80', '443:443', '22:22'],
      volumes: [
        '/var/run/docker.sock:/var/run/docker.sock:ro',  // discover labelled containers
        './files/traefik.yml:/etc/traefik/traefik.yml:ro',
        './files/host.yml:/etc/traefik/dynamic/host.yml:ro',           // shared dynamic config
        './files/controller/controller.yaml:/etc/traefik/dynamic/controller.yaml:ro',  // central routing table
        roles.app + ':/letsencrypt',  // persist acme.json across redeploys (volume keyed below)
      ],
      networks: {
        [reg.sharedNetworks[proxyNetwork].name]: {
          aliases: [extName]
        },
      },
      healthcheck: {
        test: ['CMD', 'traefik', 'healthcheck', '--ping'],
        interval: '30s',
        timeout: '5s',
        retries: 3,
        start_period: '20s',
      },
    },
  },

  networks: s.network.own(proxyNetwork),  // OWNS shared-proxy (creates it; deploy first)

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },  // 'traefik_app'
  },
}
