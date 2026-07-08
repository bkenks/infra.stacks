// databasus — database backup manager.
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// All identity (name, port, version, derived app name) is static and baked in
// at compile time — no .env needed at deploy. Only the Infisical-rendered
// secret arrives at runtime (bind-mounted from /dev/shm).
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'databasus';
local s = c.stack(stack);
local n = s.names;
local roles = reg.roles;

local port = 4005;
local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';

{
  name: stack,

  services: {
    [roles.app]: {
      image: 'databasus/databasus@' + version,
      volumes: [
        // Secret rendered by the Infisical agent (SECRET_KEY -> this path).
        '/dev/shm/' + stack + '_secret.key:/databasus-data/secret.key:ro',
        roles.app + ':/databasus-data',
      ],
      ports: [std.toString(port) + ':' + std.toString(port)],
      networks: {
        default: { aliases: [n.container(roles.app)] },
        [reg.sharedNetworks.dbBackups.name]: { aliases: [n.container(roles.app)] },
      },
      restart: 'unless-stopped',
    },
  },

  networks:
    s.network.default      // private net (renamed default), named 'databasus'
    + s.network.own('dbBackups'),  // databasus OWNS shared-db-backups; the DBs join it

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },  // 'databasus_app'
  },
}
