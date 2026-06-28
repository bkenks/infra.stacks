// komodo-periphery — Komodo Periphery agent (runs on every host).
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// Identity (name, image, port, version) is baked in at compile time. Only
// genuine per-HOST runtime values (DOCKER_VOLUMES) stay as ${...}.
local infra = import 'infra.libsonnet';

local stack = 'komodo-periphery';
local n = infra.net.names(stack);

local version = '2.1.2';          // Komodo image tag; keep in sync with komodo/compose.jsonnet
local port = 8120;
local vols = '${DOCKER_VOLUMES}';  // per-host volume root — runtime interpolated

{
  name: stack,

  services: {
    [stack]: {
      image: 'fj.lilbud.homektb.com/ktbgroup-self-hosted/komodo-periphery:' + version,
      container_name: n.stack,  // 'komodo-periphery'
      volumes: [
        n.volume('keys') + ':/config/keys',          // auto-generated PKI keys for v2 authentication
        '/var/run/docker.sock:/var/run/docker.sock',  // manage this host's containers
        '/proc:/proc',                                // see host processes from inside the container
        '/etc/komodo:/etc/komodo',                    // periphery agent root (same path inside and outside)
        vols + ':' + vols,                            // mirror docker volumes for directory pre-creation
        '/dev/shm/:/dev/shm/',
      ],
      env_file: ['./periphery.env'],
      ports: [infra.net.publish(port)],
      networks: {
        default: { aliases: [n.stack] },  // 'komodo-periphery' — project-independent name
      },
      labels: infra.mixins.komodoSkip,
      restart: 'unless-stopped',
      init: true,
    },
  },

  volumes: {
    // Distinct from komodo-core's keys volume (see komodo/compose.jsonnet) so PKI never cross-contaminates.
    [n.volume('keys')]: { name: n.volume('keys') },  // 'komodo-periphery-keys'
  },

  networks: infra.net.default(stack),  // private net (renamed default) 'komodo-periphery'
}
