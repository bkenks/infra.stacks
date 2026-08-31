// Static config baked in at compile time — nothing arrives at deploy but the Infisical
// secret, and databasus reads that from a file rather than from its environment.
//
// Two documents, because this stack is part of the restore tier: it has to come up on a
// cold start to restore the Infisical volume, which is exactly when the infisical-secrets
// provider cannot answer. compose.yaml is the steady state; bootstrap.yaml is the same
// stack with the provider swapped for the env file the control plane writes. They are
// alternatives, never layered — a compose override merges, so it could not drop the
// provider service or the depends_on that waits on it.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'databasus',

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
};

local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';
local port = '4005';

// Written by the control plane during a cold start, carrying SECRET_KEY under the same
// name the provider injects it as — so the hook below is identical either way.
local bootstrapEnv = '${ANSIBLE_SECRETS_FILE:-%s/%s.env}' % [lib.collections.dirs.secrets, refs.name];

// The app service. `secretsProvider` picks where SECRET_KEY comes from: the provider
// service (steady state) or the env file (bootstrap). Nothing else differs.
local app(secretsProvider) = {
  container_name: refs.app.ext,
  image: 'databasus/databasus@' + version,
  restart: lib.collections.restart.unlessStopped,
  [if secretsProvider then 'depends_on']: lib.secretsReady,
  [if !secretsProvider then 'env_file']: [bootstrapEnv],
  // databasus reads its key from a file, and neither the provider nor an env file does
  // anything but set environment variables. The hook runs before the container starts,
  // with SECRET_KEY already injected, and writes it into the data volume the container
  // then reads. `$$` escapes compose's interpolation so the shell in the hook expands it
  // rather than compose resolving it to nothing. The hook needs its own entrypoint-less
  // image: without one Compose reuses the service image, whose /app/start.sh entrypoint
  // swallows the command as arguments and never exits, hanging the deploy.
  pre_start: [{
    image: 'alpine:3.20',
    command: ['sh', '-c', 'umask 077; printf %s "$$SECRET_KEY" > /databasus-data/secret.key'],
  }],
  volumes: [refs.appData.mount('/databasus-data')],
  ports: [port + ':' + port],
  network_mode: 'host',
  // Reaches the databases it backs up over the .internal zone, which every host's
  // CoreDNS resolves (Postgres at lib.registry.endpoint.serviceGroup.postgres.host.addr);
  // configure each backup target's connection inside databasus to that address.
};

{
  compose: {
    name: refs.name,
    // No private bridge: the one service runs in the host netns.
    volumes: refs.appData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/databasus'),
      [refs.app.key]: app(true),
    },
  },

  bootstrap: {
    name: refs.name,
    volumes: refs.appData.declare,

    services: {
      [refs.app.key]: app(false),
    },
  },
}
