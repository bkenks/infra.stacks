// No interpolation env_file: config is committed ./periphery.env (service-level);
// DOCKER_VOLUMES comes from Komodo's stack Environment.
//
// The stack is named `komodo` (so its resources sit beside komodo-core's), while the
// deployed directory — and so the compose project — is komodo-periphery.
local lib = import 'lib.libsonnet';
local reg = lib.registry;

local name = 'komodo';
local periphery = 'periphery';

local version = '2.1.2';          // Komodo image tag; keep in sync with komodo/stack.jsonnet
local port = 8120;

lib.render(
  'komodo-periphery',
  lib.Stack(name, function(ref) {
    [periphery]: lib.Service {
      image: 'ghcr.io/moghtech/komodo-periphery:' + version,
      // Distinct from komodo-core's keys volume (see komodo/stack.jsonnet) so PKI never
      // cross-contaminates.
      volumes_:: { periphery: '/config/keys' },  // auto-generated PKI keys for v2 auth
      mounts_:: [
        '/var/run/docker.sock:/var/run/docker.sock',
        '/proc:/proc',
        '/etc/komodo:/etc/komodo',  // same path inside and outside
        '/dev/shm/:/dev/shm/:ro',
        reg.dirs.docker.root + ':' + reg.dirs.docker.root,  // mirrored path, needed for directory pre-creation
      ],
      env_file: ['./periphery.env'],
      ports: [port + ':' + port],
      labels: lib.komodoSkip,
      init: true,
    },
  }),
)
