// scriberr — self-hosted audio transcription (WhisperX), business use. Renders
// to compose.stack.yaml — do not edit the YAML. Joins shared-proxy (traefik
// owns) to be reachable.
local lib = import 'lib.libsonnet';

local stack = 'scriberr';
local n = lib.compose.names(stack);
local app = lib.registry.roles.app;

// app owns two volumes, so each resource key is suffixed with its purpose
// (<service-role>_<purpose>) instead of the bare role — see docker-compose.md.
local dataVol = app + '_data';
local whisperxVol = app + '_whisperx-env';

local port = 8080;

{
  name: stack,

  services: {
    [app]: {
      // Pinned by digest (upstream has no stable version tags) — do not
      // replace with a floating tag.
      image: 'ghcr.io/rishikanthc/scriberr@sha256:9e36448fb5a6003b28cd3d9ac783e8cbef5ed916936c20ec353a55fa380484f4',
      container_name: n.container(app),
      volumes: [
        dataVol + ':/app/data',
        whisperxVol + ':/app/whisperx-env',
      ],
      environment: {
        APP_ENV: 'production',
        PUID: '1000',
        PGID: '1000',
        ALLOWED_ORIGINS: 'https://' + stack + '.' + lib.registry.domains.ktbinternal,
      },
      restart: 'unless-stopped',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.alias(app)] },
        [lib.registry.sharedNetworks.proxy.name]: { aliases: [n.alias(app)] },
      },
      labels: lib.mixins.proxyAdd(stack, stack, port),
    },
  },

  volumes: {
    [dataVol]: { name: n.volume(dataVol) },
    [whisperxVol]: { name: n.volume(whisperxVol) },
  },

  networks: n.network + lib.compose.join('proxy'),
}
