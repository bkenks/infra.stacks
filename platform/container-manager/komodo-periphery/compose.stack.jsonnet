// komodo-periphery — Komodo Periphery agent (runs on every host).
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Identity (name, image, port, version) is baked in at compile time. Only
// genuine per-HOST runtime values (DOCKER_VOLUMES) stay as ${...}.
local lib = import 'lib.libsonnet';
local r = lib.registry;
local c = lib.compose;

local stack = 'komodo';
local n = c.names(stack);
local p = {
  role: 'periphery',
  extName: n.container(self.role),
  keysVolume: n.volume(self.role) + '-keys'
};

local version = '2.1.2';          // Komodo image tag; keep in sync with komodo/compose.jsonnet
local port = 8120;

{
  name: stack,

  services: {
    [p.role]: {
      image: 'ghcr.io/moghtech/komodo-periphery' + version,
      container_name: p.extName,  // 'komodo-periphery'
      volumes: [
        p.keysVolume + ':/config/keys',          // auto-generated PKI keys for v2 authentication
        '/var/run/docker.sock:/var/run/docker.sock',  // manage this host's containers
        '/proc:/proc',                                // see host processes from inside the container
        '/etc/komodo:/etc/komodo',                    // periphery agent root (same path inside and outside)
        '/dev/shm/:/dev/shm/',
        r.dockerVolumes + ':' + r.dockerVolumes,                            // mirror docker volumes for directory pre-creation
      ],
      env_file: ['./periphery.env'],
      ports: [lib.compose.publish(port)],
      networks: {
        default: {
          aliases: [p.extName]
        },  // 'komodo-periphery' — project-independent name
      },
      labels: lib.mixins.komodoSkip,
      restart: 'unless-stopped',
      init: true,
    },
  },

  volumes: {
    // Distinct from komodo-core's keys volume (see komodo/compose.jsonnet) so PKI never cross-contaminates.
    [p.keysVolume]: {
      name: p.keysVolume  // 'komodo-periphery-keys'
    },
  },

  networks: n.network,  // private net (renamed default) 'komodo-periphery'
}
