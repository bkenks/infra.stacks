local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local nameStack = 'newt';
local stack = c.stack(nameStack);

local composeChild(instanceType) = 'compose.' + instanceType + '.yaml';  // bare — it's an output-file key
local secretsEnv(instanceType)   = reg.secretDir + '/' + nameStack + '.' + instanceType + '.env';

local vars = {
  newt: { version: '1.14.0', role: 'tunnel', sharedProxy: reg.sharedNetworks.proxy.name },
};

local variants = ['internal', 'external'];

// Child compose body for one newt instance. Returns { services, networks } — caller names the file.
local newt(instanceType) =
  local svcName = instanceType + '-' + stack.names.container(vars.newt.role);
  {
    services: {
      [svcName]: {
        image: 'fosrl/newt:' + vars.newt.version,
        container_name: svcName,
        profiles: [instanceType],
        restart: 'unless-stopped',
        networks: { [vars.newt.sharedProxy]: { aliases: [svcName] } },
        extra_hosts: ['host.docker.internal:host-gateway'],
        env_file: ['./envs/' + nameStack + '.' + instanceType + '.env'],  // Pangolin URL
        environment: {
          TZ: 'America/New_York',
          NEWT_ID: '${NEWT_ID:?err}',
          NEWT_SECRET: '${NEWT_SECRET:?err}',
        },
      },
    },
    networks: stack.network.join(reg.sharedNetworks.proxy),
  };

{
  [reg.composeFiles.parent]: {
    name: nameStack,
    include: [
      { path: './' + composeChild(v), env_file: secretsEnv(v) }
      for v in variants
    ],
  },
} + {
  [composeChild(v)]: newt(v)
  for v in variants
}