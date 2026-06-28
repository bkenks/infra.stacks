// traefik — this host's reverse proxy + TLS terminator. Owner of shared-proxy.
//
// Renders to compose.yaml — do not edit the YAML. Traefik creates shared-proxy
// (deploy it FIRST; consumers join it external). Service discovery is pinned to
// shared-proxy in files/traefik.yml (providers.docker.network) — keep in sync.
local lib = import 'lib.libsonnet';

local stack = 'traefik';
local n = lib.compose.names(stack);
local version = 'v3.6.7';  // >= v3.6.1 so Docker 29 API negotiation works

{
  name: stack,

  services: {
    traefik: {
      image: 'docker.io/library/traefik:' + version,
      restart: 'unless-stopped',
      environment: {
        TZ: 'America/New_York',
        // Secret — CF_DNS_API_TOKEN for the Cloudflare DNS-01 ACME challenge (lego
        // reads it from the container env). Interpolated from /dev/shm/node_traefik.env
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
        './files/controller/controller.yml:/etc/traefik/dynamic/controller.yml:ro',  // central routing table
        'letsencrypt:/letsencrypt',  // persist acme.json across redeploys (volume keyed below)
      ],
      networks: {
        [lib.compose.netName('proxy')]: { aliases: [stack] },  // alias 'traefik' on shared-proxy
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

  networks: lib.compose.own('proxy'),  // OWNS shared-proxy (creates it; deploy first)

  volumes: {
    letsencrypt: { name: n.volume('letsencrypt') },  // 'traefik-letsencrypt'
  },
}
