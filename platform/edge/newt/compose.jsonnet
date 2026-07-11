local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'newt';
local s = c.stack(stack);
local n = s.names;
local nw = {
  version: '1.14.0',
  role: 'tunnel',
  extName: n.container(self.role),
  baseEnvironment(domain):: {
    PANGOLIN_ENDPOINT: 'https://pangolin.' + domain,
    TZ: 'America/New_York',
    // Secrets rendered from Infisical infra project folder /roles/traefik-controller.
    NEWT_ID: '${NEWT_ID:?err}',
    NEWT_SECRET: '${NEWT_SECRET:?err}',
  },
};

local manifest = {
  name: stack,

  services: {
    [nw.role]: {
      image: 'fosrl/newt:' + nw.version,
      container_name: nw.extName,
      environment: nw.baseEnvironment(reg.domains.ktbinternal),
      restart: 'unless-stopped',
      networks: {
        [reg.sharedNetworks.proxy.name]: { aliases: [nw.extName] },
      },
      extra_hosts: ['host.docker.internal:host-gateway'],
    },
  },

  networks:
    s.network.default   // unused here — no peers
    + s.network.join(reg.sharedNetworks.proxy),  // owned by traefik
};

local base = c.render(stack, manifest, [secrets.newt.path]);

base + {
  'compose.external.yaml': {
    services: {
      [nw.role]: { environment: nw.baseEnvironment(reg.domains.ktbcloud) }, // Build override compose to swap url
    },
  },
  'compose.yaml'+: {
    'include'+: [ { path: './compose.external.yaml' } ]
  }
}
