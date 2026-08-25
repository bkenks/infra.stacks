// Static config baked in at compile time — nothing arrives at deploy but the Infisical
// secret, and databasus reads that from a file rather than from its environment.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'databasus',

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
};

local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';
local port = '4005';

{
  compose: {
    name: refs.name,
    // No private bridge: the one service runs in the host netns.
    volumes: refs.appData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('databasus'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'databasus/databasus@' + version,
        restart: lib.collections.restart.unlessStopped,
        depends_on: lib.secretsReady,
        // databasus reads its key from a file, and the provider only ever injects
        // environment variables. The hook runs in this service's own image before the
        // container starts, with SECRET_KEY already injected, and writes it into the data
        // volume the container then reads. `$$` escapes compose's interpolation so the
        // shell in the hook expands it rather than compose resolving it to nothing.
        pre_start: [{
          command: ['sh', '-c', 'umask 077; printf %s "$$SECRET_KEY" > /databasus-data/secret.key'],
        }],
        volumes: [refs.appData.mount('/databasus-data')],
        ports: [port + ':' + port],
        network_mode: 'host',
        // Reaches the databases it backs up over the .internal zone, which every host's
        // CoreDNS resolves (Postgres at lib.registry.endpoint.serviceGroup.postgres.host.addr);
        // configure each backup target's connection inside databasus to that address.
      },
    },
  },
}
