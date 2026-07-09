// Static config baked in at compile time — no .env at deploy; only the Infisical secret
// arrives at runtime (bind-mounted from /dev/shm). No env_file: databasus's only secret is
// a raw key file bind-mounted from /dev/shm, not an env var.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'databasus';
local s = c.stack(stack);
local n = s.names;
local roles = reg.roles;

local port = 4005;
local version = 'sha256:f748c20cecb3cf3162d80ebfddd4f192b5e4ee640d600c9daf726310ac49e51c';

local manifest = {
  name: stack,

  services: {
    [roles.app]: {
      image: 'databasus/databasus@' + version,
      volumes: [
        // Rendered by Infisical agent (SECRET_KEY) — a raw key file, not an env_file,
        // so it is bind-mounted rather than passed to include.env_file.
        secrets[stack].path + ':/databasus-data/secret.key:ro',
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
    s.network.default
    + s.network.own('dbBackups'),  // databasus OWNS shared-db-backups; the DBs join it

  volumes: {
    [roles.app]: { name: n.volume(roles.app) },
  },
};

c.render(stack, manifest)
