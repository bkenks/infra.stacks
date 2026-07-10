// Traefik creates shared-proxy (deploy it FIRST; consumers join it external). Service
// discovery is pinned to shared-proxy in files/traefik.yml (providers.docker.network) — keep in sync.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;
local roles = reg.roles;

local stack = 'traefik';
local s = c.stack(stack);
local n = s.names;
local version = 'v3.6.7';  // >= v3.6.1 so Docker 29 API negotiation works

local proxyNetwork = reg.sharedNetworks.proxy;

local manifest = {
  name: stack,

  services: {
    [roles.app]: {
      local extName = n.container(roles.app),

      image: 'docker.io/library/traefik:' + version,
      container_name: extName,
      restart: 'unless-stopped',
      // Hard memory ceiling: without it a request spike (e.g. a controller-table routing
      // loop) can consume all host RAM; with it, cgroup OOM-kills just Traefik and
      // restart:unless-stopped brings it back. GOMEMLIMIT keeps GC aggressive well under
      // this so it rarely trips on legitimate load.
      mem_limit: '1g',
      environment: {
        TZ: 'America/New_York',
        GOMEMLIMIT: '750MiB',
        CF_DNS_API_TOKEN: '${CF_DNS_API_TOKEN:?err}',
      },
      // Traefik owns 80/443. :22 is Forgejo git-over-SSH — needs admin sshd moved off 22
      // first (infra.ansible), else the bind conflicts.
      ports: ['80:80', '443:443', '22:22'],
      volumes: [
        '/var/run/docker.sock:/var/run/docker.sock:ro',
        './files/traefik.yml:/etc/traefik/traefik.yml:ro',
        './files/host.yml:/etc/traefik/dynamic/host.yml:ro',
        './files/controller/controller.yaml:/etc/traefik/dynamic/controller.yaml:ro',
        roles.app + ':/letsencrypt',  // persist acme.json across redeploys
      ],
      networks: {
        [proxyNetwork.name]: {
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

  networks: s.network.own(proxyNetwork),

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },
  },
};

c.render(stack, manifest, [
  secrets['cloudflare__dns-api-token'].platformPath,
])
