// Static config baked in at compile time — no .env at deploy; only the Infisical secret
// arrives at runtime (bind-mounted from /dev/shm). No env_file: databasus's only secret is
// a raw key file bind-mounted from /dev/shm, not an env var.
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'databasus';
local port = 4005;
local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'databasus/databasus@' + version,
      volumes_:: { app: '/databasus-data' },
      // Rendered by Infisical agent (SECRET_KEY) — a raw key file, not an env_file,
      // so it is bind-mounted rather than passed to include.env_file.
      mounts_:: [lib.Secret('databasus') + ':/databasus-data/secret.key:ro'],
      ports: [std.toString(port) + ':' + std.toString(port)],
      // Reaches the databases it backs up over the docker host-gateway (they publish host
      // ports now — e.g. Postgres at host.docker.internal:6109); configure each backup
      // target's connection inside databasus to that address.
      extra_hosts: ['host.docker.internal:host-gateway'],
    },
  }),
)
