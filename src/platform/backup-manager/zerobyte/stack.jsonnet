// Reads /var/lib/docker/volumes off the host (a bind mount, not a docker network), so it
// owns no shared network. BASE_URL points at the control plane rather than at whichever
// host this copy runs on, so every instance advertises the same address.
//
// Two documents, because this stack is part of the restore tier: it has to come up on a
// cold start alongside databasus, which is exactly when the infisical-secrets provider
// cannot answer. compose.yaml is the steady state; bootstrap.yaml is the same stack with
// the provider swapped for the env file the control plane writes. They are alternatives,
// never layered — a compose override merges, so it could not drop the provider service or
// the depends_on that waits on it.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'zerobyte',

  app:: self.Service { role:: lib.collections.role.APP },
  appData:: self.Volume { key:: 'app' },
};

local version = 'v0.40';
local port = '4096';

// Written by the control plane during a cold start, carrying APP_SECRET under the same
// name the provider injects it as.
local bootstrapEnv = '${ANSIBLE_SECRETS_FILE:-%s/%s.env}' % [lib.collections.dirs.secrets, refs.name];

// The app service. `secretsProvider` picks where APP_SECRET comes from: the provider
// service (steady state) or the env file (bootstrap). Nothing else differs.
local app(secretsProvider) = {
  container_name: refs.app.ext,
  image: 'ghcr.io/nicotsx/zerobyte:' + version,
  restart: lib.collections.restart.unlessStopped,
  [if secretsProvider then 'depends_on']: lib.secretsReady,
  [if !secretsProvider then 'env_file']: [bootstrapEnv],
  volumes: [
    refs.appData.mount('/var/lib/zerobyte'),
    '/etc/localtime:/etc/localtime:ro',
    '/var/lib/docker/volumes:/source/docker-volumes',
  ],
  // APP_SECRET arrives from infisical-secrets, or from the bootstrap env file.
  environment: {
    TZ: 'America/New_York',
    BASE_URL: 'http://%s:%s' % [lib.registry.endpoint.hostGroup.littlebuddy.ref, port],
  },
  // Core infra, no proxy in front of it.
  ports: [port + ':' + port],
  cap_add: ['SYS_ADMIN'],
  devices: ['/dev/fuse:/dev/fuse'],
  security_opt: ['apparmor:unconfined'],
};

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('infra', '/zerobyte'),
      [refs.app.key]: app(true),
    },
  },

  bootstrap: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [refs.app.key]: app(false),
    },
  },
}
