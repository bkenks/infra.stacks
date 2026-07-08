// scriberr — self-hosted audio transcription (WhisperX), business use. Renders
// to compose.stack.yaml — do not edit the YAML. Joins shared-proxy (traefik
// owns) to be reachable.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'scriberr';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

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
        ALLOWED_ORIGINS: 'https://' + stack + '.' + reg.domains.ktbinternal,
      },
      restart: 'unless-stopped',
      expose: [std.toString(port)],
      networks: {
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add(stack, stack, port),
    },
  },

  volumes: {
    [dataVol]: { name: n.volume(dataVol) },
    [whisperxVol]: { name: n.volume(whisperxVol) },
  },

  networks: s.network.default + s.network.join('proxy'),
}
