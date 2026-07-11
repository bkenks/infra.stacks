local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'newt';
local s = c.stack(stack);
local n = s.names;

local runtimeVars = {
  NEWT_VARIANT: "${NEWT_VARIANT:?must be 'internal' or 'external'}",
};

local nw = {
  version: '1.14.0',
  role: 'tunnel',
  extName: runtimeVars.NEWT_VARIANT + n.container(self.role),
  envFilename: stack + '.' + runtimeVars.NEWT_VARIANT + ".env",
};

local manifest = {
  name: stack,

  services: {
    [nw.role]: {
      image: 'fosrl/newt:' + nw.version,
      container_name: nw.extName,
      env_file: [ './envs/' + nw.envFilename],
      environment: {
        TZ: 'America/New_York',
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
    + s.network.join(reg.sharedNetworks.proxy),  // owned by traefik
};

c.render( stack, manifest, [ reg.secretDir + "/" + nw.envFilename ] )
