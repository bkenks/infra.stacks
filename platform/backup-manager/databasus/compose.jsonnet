// databasus — database backup manager.
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// All identity (name, port, version, derived app name) is static and baked in
// at compile time — no .env needed at deploy. Only the Infisical-rendered
// secret arrives at runtime (bind-mounted from /dev/shm).
local lib = import 'lib.libsonnet';

local stack = 'databasus';
local n = lib.compose.names(stack);
local roles = lib.compose.roles;

local port = 4005;
local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';

{
  name: stack,

  services: {
    [roles.app]: {
      image: 'databasus/databasus@' + version,
      profiles: [stack],
      volumes: [
        // Secret rendered by the Infisical agent (SECRET_KEY -> this path).
        '/dev/shm/' + stack + '_secret.key:/databasus-data/secret.key:ro',
        roles.app + ':/databasus-data',
      ],
      ports: [lib.compose.publish(port)],
      networks: {
        default: { aliases: [n.alias(roles.app)] },
        [lib.compose.netName('dbBackups')]: { aliases: [n.alias(roles.app)] },
      },
      restart: 'unless-stopped',
    },
  },

  networks:
    n.network      // private net (renamed default), named 'databasus'
    + lib.compose.own('dbBackups'),  // databasus OWNS shared-db-backups; the DBs join it

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },  // 'databasus-app'
  },
}
