// NEWT_ID/NEWT_SECRET come from the newt bundle the Infisical agent renders. The control
// server's URL is not a secret and not per-host, so it is read straight out of the
// registry — the same value pangolin publishes itself at.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = '1.14.0';

{
  name: refs.name,
  networks: refs.networks,

  services: {
    [refs.tunnel.key]: {
      container_name: refs.tunnel.container,
      image: 'fosrl/newt:' + version,
      restart: lib.restart.unlessStopped,
      extra_hosts: lib.hostGateway.extraHosts,
      environment: {
        TZ: 'America/New_York',
        PANGOLIN_ENDPOINT: lib.registry.endpoint.pangolin.public.url,
        NEWT_ID: '${NEWT_ID:?err}',
        NEWT_SECRET: '${NEWT_SECRET:?err}',
      },
    },
  },
}
