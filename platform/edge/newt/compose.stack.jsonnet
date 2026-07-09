local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'newt';
local s = c.stack(stack);
local n = s.names;
local nw = {
  version: '1.14.0',
  role: 'tunnel',
  extName: n.container(self.role),
};

{
  name: stack,

  services: {
    [nw.role]: {
      image: 'fosrl/newt:' + nw.version,
      container_name: nw.extName,
      environment: {
        TZ: 'America/New_York',
        PANGOLIN_ENDPOINT: 'https://pangolin.' + reg.domains.ktbinternal,
        // Secrets rendered from Infisical infra project folder /roles/traefik-controller.
        NEWT_ID: '${NEWT_ID:?err}',
        NEWT_SECRET: '${NEWT_SECRET:?err}',
      },
      restart: 'unless-stopped',
      networks: {
        [reg.sharedNetworks.proxy.name]: { aliases: [nw.extName] },
      },
      extra_hosts: ['host.docker.internal:host-gateway'],
    },
  },

  networks:
    s.network.default   // unused here — no peers
    + s.network.join('proxy'),  // owned by traefik
}
