// Static config baked in at compile time — nothing arrives at deploy but the Infisical
// secret, which the agent renders as a raw key file.
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';
local port = '4005';

{
  name: refs.name,
  // No private bridge: the one service runs in the host netns.
  volumes: refs.appData.declare,

  services: {
    [refs.app.key]: {
      container_name: refs.app.container,
      image: 'databasus/databasus@' + version,
      restart: lib.restart.unlessStopped,
      volumes: [
        refs.appData.mount('/databasus-data'),
        // SECRET_KEY, rendered by the Infisical agent as a raw key file.
        lib.Secret('databasus') + ':/databasus-data/secret.key:ro',
      ],
      ports: [port + ':' + port],
      network_mode: 'host',
      // Reaches the databases it backs up over the docker gateway — they publish host
      // ports (Postgres at lib.registry.endpoint.postgres.host.addr); configure each
      // backup target's connection inside databasus to that address.
      extra_hosts: lib.hostGateway.extraHosts,
    },
  },
}
