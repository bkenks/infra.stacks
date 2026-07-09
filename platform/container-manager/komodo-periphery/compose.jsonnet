// No interpolation env_file: config is committed ./periphery.env (service-level);
// DOCKER_VOLUMES comes from Komodo's stack Environment.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'komodo';
local s = c.stack(stack);
local n = s.names;
local p = {
  role: 'periphery',
  extName: n.container(self.role),
  volumeExtName: n.volume(self.role),
};

local version = '2.1.2';          // Komodo image tag; keep in sync with komodo/compose.jsonnet
local port = 8120;

local manifest = {
  name: stack,

  services: {
    [p.role]: {
      image: 'ghcr.io/moghtech/komodo-periphery:' + version,
      container_name: p.extName,
      volumes: [
        p.role + ':/config/keys',          // auto-generated PKI keys for v2 auth
        '/var/run/docker.sock:/var/run/docker.sock',
        '/proc:/proc',
        '/etc/komodo:/etc/komodo',                    // same path inside and outside
        '/dev/shm/:/dev/shm/:ro',
        reg.server.dir.docker.root + ':' + reg.server.dir.docker.root,  // mirrored path, needed for directory pre-creation
      ],
      env_file: ['./periphery.env'],
      ports: [port + ':' + port],
      networks: {
        default: {
          aliases: [p.extName]  // project-independent name
        },
      },
      labels: s.komodoSkip,
      restart: 'unless-stopped',
      init: true,
    },
  },

  volumes: {
    // Distinct from komodo-core's keys volume (see komodo/compose.jsonnet) so PKI never cross-contaminates.
    [p.role]: {
      name: p.volumeExtName
    },
  },

  networks: s.network.default,
};

c.render('komodo-periphery', manifest)
