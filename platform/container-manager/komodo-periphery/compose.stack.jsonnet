// komodo-periphery — Komodo Periphery agent (runs on every host).
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Identity (name, image, port, version) is baked in at compile time. Only
// genuine per-HOST runtime values (DOCKER_VOLUMES) stay as ${...}.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'komodo';
local s = c.stack(stack);
local n = s.names;
local p = {
  role: 'periphery',
  extName: n.container(self.role),
  // Single volume for this service: resource key matches the service role
  // exactly (no extra suffix); only the external name gets the project
  // prefix — see docker-compose.md naming convention.
  volumeExtName: n.volume(self.role),
};

local version = '2.1.2';          // Komodo image tag; keep in sync with komodo/compose.jsonnet
local port = 8120;

{
  name: stack,

  services: {
    [p.role]: {
      image: 'ghcr.io/moghtech/komodo-periphery:' + version,
      container_name: p.extName,  // 'komodo_periphery'
      volumes: [
        p.role + ':/config/keys',          // auto-generated PKI keys for v2 authentication
        '/var/run/docker.sock:/var/run/docker.sock',  // manage this host's containers
        '/proc:/proc',                                // see host processes from inside the container
        '/etc/komodo:/etc/komodo',                    // periphery agent root (same path inside and outside)
        '/dev/shm/:/dev/shm/:ro',
        reg.server.dir.docker.root + ':' + reg.server.dir.docker.root,                            // mirror docker volumes for directory pre-creation
      ],
      env_file: ['./periphery.env'],
      ports: [port + ':' + port],
      networks: {
        default: {
          aliases: [p.extName]
        },  // 'komodo_periphery' — project-independent name
      },
      labels: s.komodoSkip,
      restart: 'unless-stopped',
      init: true,
    },
  },

  volumes: {
    // Distinct from komodo-core's keys volume (see komodo/compose.jsonnet) so PKI never cross-contaminates.
    [p.role]: {
      name: p.volumeExtName  // 'komodo_periphery'
    },
  },

  networks: s.network.default,  // private net (renamed default) 'komodo-periphery'
}
