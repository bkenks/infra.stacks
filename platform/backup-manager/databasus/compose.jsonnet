// databasus — database backup manager.
//
// Source of truth: this file compiles to compose.yaml (do not edit the YAML).
// All identity (name, port, version, derived app name) is static and baked in
// at compile time — no .env needed at deploy. Only the Infisical-rendered
// secret arrives at runtime (bind-mounted from /dev/shm).
local infra = import 'infra.libsonnet';

local stack = 'databasus';
local n = infra.net.names(stack);

local port = 4005;
local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';

{
  name: stack,

  services: {
    app: {
      image: 'databasus/databasus@' + version,
      profiles: [stack],
      volumes: [
        // Secret rendered by the Infisical agent (SECRET_KEY -> this path).
        '/dev/shm/' + stack + '_secret.key:/databasus-data/secret.key:ro',
        'app:/databasus-data',
      ],
      ports: [infra.net.publish(port)],
      networks: {
        default: { aliases: [n.alias('app')] },
        [infra.net.netName('dbBackups')]: { aliases: [n.alias('app')] },
      },
      restart: 'unless-stopped',
    },
  },

  networks:
    infra.net.default(stack)      // private net (renamed default), named 'databasus'
    + infra.net.own('dbBackups'),  // databasus OWNS shared-db-backups; the DBs join it

  volumes: {
    app: { name: n.volume('app') },  // 'databasus-app'
  },
}
