local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local nameStack = 'newt';
local stack = c.stack(nameStack);

local vars = {
  newt: { version: '1.14.0', role: 'tunnel' },
};

local svcName = stack.names.container(vars.newt.role);

local manifest = {
  services: {
    [svcName]: {
      image: 'fosrl/newt:' + vars.newt.version,
      container_name: svcName,
      restart: 'unless-stopped',
      extra_hosts: ['host.docker.internal:host-gateway'],
      env_file: ['./envs/newt.env'],  // PANGOLIN_ENDPOINT (control-server URL)
      environment: {
        TZ: 'America/New_York',
        NEWT_ID: '${NEWT_ID:?err}',
        NEWT_SECRET: '${NEWT_SECRET:?err}',
      },
    },
  },
};

// NEWT_ID/NEWT_SECRET come from /dev/shm/newt.env (infisical-agent).
c.render(nameStack, manifest, [reg.secretDir + '/newt.env'])
